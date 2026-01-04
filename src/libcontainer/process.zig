const std = @import("std");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const ocispec = @import("ocispec");
const process = @import("process.zig");
const filesystem = @import("filesystem.zig");
const namespace = @import("namespace.zig");
const mount = @import("mount.zig");
const channel = @import("channel.zig");
const runtime = @import("runtime.zig");
const clone = @import("clone.zig");
const channelAction = channel.PChannelAction;
const posix = std.posix;
const linux = std.os.linux;
const runtimeSpec = ocispec.runtime.Spec;

const DEFAULT_HOSTNAME: []const u8 = "thorcon";

const uinstd = @cImport({
    @cInclude("unistd.h");
});

pub fn processPrep(opts: *runtime.RuntimeOptions) void {
    const pid = std.os.linux.getpid();
    // setup cgroup

    // unshare newuser namespace
    switch (linux.E.init(linux.unshare(linux.CLONE.NEWUSER))) {
        .SUCCESS => {},
        else => |err| {
            std.log.err("pid {} failed to set unshare newuser: {any}", .{ pid, err });

            unreachable;
        },
    }

    opts.pcomm.send(channelAction.UserMapRequest, null) catch {
        unreachable;
    };

    std.log.debug("pid {} waiting for action {any}", .{ pid, channelAction.UserMapOK });
    while (true) {
        const recvData = opts.ccomm.receive() catch unreachable;
        const ccomm = recvData.@"0";

        switch (ccomm) {
            channelAction.UserMapOK => {
                std.log.debug("pid {} action {any} received", .{ pid, channelAction.UserMapOK });

                containerSetUidAndGid(pid, 0, 0) catch |err| {
                    std.log.err("pid {} failed to set uid/gid: {any}", .{ pid, err });

                    unreachable;
                };

                break;
            },
            else => {},
        }
    }

    switch (linux.E.init(linux.unshare(linux.CLONE.NEWPID))) {
        .SUCCESS => {},
        else => |err| {
            std.log.err("pid {} failed to set unshare newuser: {any}", .{ pid, err });

            unreachable;
        },
    }

    const Args = std.meta.Tuple(&.{*runtime.RuntimeOptions});
    const args: Args = .{opts};

    var unshareFlags: u32 = 0;
    if (opts.runtimeSpec.linux) |rlinux| {
        if (rlinux.namespaces) |namespaces| {
            unshareFlags = @intCast(namespace.getUnshareFlags(pid, namespaces));
        }
    }

    const childPID = clone.clone(unshareFlags, process.processInit, args) catch |err| {
        std.log.err("pid {} failed clone init process: {any}", .{ pid, err });

        unreachable;
    };

    opts.pcomm.send(channelAction.Init, childPID) catch {
        unreachable;
    };

    std.log.debug("pid {} process init cloned {}", .{ pid, childPID });
}

pub fn processInit(opts: *runtime.RuntimeOptions) void {
    const pid = std.os.linux.getpid();
    std.log.debug("pid {} process init started", .{pid});

    // set uid=0 and gid=0
    containerSetUidAndGid(pid, 0, 0) catch |err| {
        std.log.err("pid {} set uid and gid error: {any}", .{ pid, err });

        unreachable;
    };

    // mount rootfs
    mount.mountContainerRootFs(pid, opts.rootfs) catch |err| {
        std.log.err("pid {} mount rootfs: {any}", .{ pid, err });

        unreachable;
    };

    // mount filesystems
    mount.mountContainerMounts(pid, opts.runtimeSpec) catch |err| {
        std.log.err("pid {}: {any}", .{ pid, err });

        unreachable;
    };

    // set masked path
    mount.setContainerMaskedPath(pid, opts.runtimeSpec) catch |err| {
        std.log.err("pid {}: {any}", .{ pid, err });

        // unreachable;
    };

    // set readonly path
    mount.setContainerReadOnlyPath(pid, opts.runtimeSpec) catch |err| {
        std.log.err("pid {}: {any}", .{ pid, err });

        // unreachable;
    };

    // pivot root or chroot to rootfs
    if (opts.noPivot) {
        filesystem.setChrootRootFs(pid, opts.rootfs) catch |err| {
            std.log.err("pid {} chroot error: {any}", .{ pid, err });

            unreachable;
        };
    } else {
        filesystem.setPivotRootFs(pid, opts.rootfs) catch |err| {
            std.log.err("pid {} pivot_root error: {any}", .{ pid, err });

            unreachable;
        };
    }

    // set rest of env

    // setup hostname
    var hostname = DEFAULT_HOSTNAME;
    if (opts.runtimeSpec.hostname) |cnthostname| {
        hostname = cnthostname;
    }

    containerSetHostname(pid, hostname) catch |err| {
        std.log.err("pid {} set hostname error: {any}", .{ pid, err });

        unreachable;
    };

    // set domain name
    if (opts.runtimeSpec.domainname) |cntdomainname| {
        containerSetDomainname(pid, cntdomainname) catch |err| {
            std.log.err("pid {} set domain name error: {any}", .{ pid, err });

            unreachable;
        };
    }

    // set working directory, uid and gid
    if (opts.runtimeSpec.process) |cprocess| {
        containerSetCwd(pid, cprocess.cwd) catch |err| {
            std.log.err("pid {} set working directory error: {any}", .{ pid, err });

            unreachable;
        };

        containerSetUidAndGid(pid, cprocess.user.uid, cprocess.user.gid) catch |err| {
            std.log.err("pid {} set uid and gid error: {any}", .{ pid, err });

            unreachable;
        };
    }

    opts.pcomm.send(channelAction.Ready, null) catch {
        unreachable;
    };

    std.log.debug("pid {} waiting for action {any}", .{ pid, channelAction.Start });
    while (true) {
        const recvData = opts.ccomm.receive() catch unreachable;
        const actval = recvData.@"0";
        switch (actval) {
            channelAction.Start => {
                std.log.debug("pid {} action {any} received", .{ pid, channelAction.Start });

                break;
            },
            else => {},
        }
    }

    // execute CMD and set ENV paths
    switch (linux.E.init(linux.execve("/bin/sh", &.{ "sh", null }, &.{null}))) {
        .SUCCESS => {},
        else => |err| {
            std.log.debug("pid {} execve error: {any}", .{ pid, err });

            unreachable;
        },
    }
}

fn containerSetCwd(pid: i32, path: []const u8) !void {
    if (path.len != 0) {
        posix.chdir(path) catch |err| {
            std.log.err("pid {} container failed to changed directory to {s}: {any}", .{ pid, path, err });
            unreachable;
        };
    }
}

fn containerSetHostname(pid: i32, hostname: []const u8) !void {
    // TODO - at the moment we need glibc uinstd sethostname function
    // in future if its part of zig then remove from here and build script
    const result = uinstd.sethostname(hostname.ptr, hostname.len);
    switch (linux.E.init(@intCast(result))) {
        .SUCCESS => {},
        else => |err| {
            std.log.debug("pid {} container set hostname error: {any}", .{ pid, err });
            unreachable;
        },
    }
}

fn containerSetDomainname(pid: i32, domainname: []const u8) !void {
    // TODO - at the moment we need glibc uinstd setdomainname function
    // in future if its part of zig then remove from here and build script
    const result = uinstd.setdomainname(domainname.ptr, domainname.len);
    switch (linux.E.init(@intCast(result))) {
        .SUCCESS => {},
        else => |err| {
            std.log.debug("pid {} container set domainname error: {any}", .{ pid, err });

            unreachable;
        },
    }
}

fn containerSetUidAndGid(pid: i32, uid: u32, gid: u32) !void {
    const uresult = uinstd.setuid(uid);
    if (uresult < 0) {
        return errors.Error.ContainerProcessUIDError;
    }

    switch (linux.E.init(@intCast(uresult))) {
        .SUCCESS => {},
        else => |err| {
            std.log.debug("pid {} container set uid error: {any}", .{ pid, err });

            unreachable;
        },
    }

    const gresult = uinstd.setuid(gid);
    if (gresult < 0) {
        return errors.Error.ContainerProcessGIDError;
    }

    switch (linux.E.init(@intCast(gresult))) {
        .SUCCESS => {},
        else => |err| {
            std.log.debug("pid {} container set gid error: {any}", .{ pid, err });

            unreachable;
        },
    }
}
