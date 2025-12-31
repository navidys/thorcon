const std = @import("std");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const ocispec = @import("ocispec");
const process = @import("process.zig");
const filesystem = @import("filesystem.zig");
const namespace = @import("namespace.zig");
const mount = @import("mount.zig");
const channel = @import("channel.zig");
const channelAction = channel.PChannelAction;
const posix = std.posix;
const linux = std.os.linux;
const runtime = ocispec.runtime;

const DEFAULT_HOSTNAME: []const u8 = "thorcon";

const uinstd = @cImport({
    @cInclude("unistd.h");
});

pub fn prepareAndExecute(rootfs: []const u8, spec: runtime.Spec, noPivot: bool, pcomm: *channel.PChannel, ccomm: *channel.PChannel) void {
    const pid = std.os.linux.getpid();

    //namespace.setContainerNamespaces(pid, spec) catch |err| {
    //    std.log.debug("pid {} container name space: {any}", .{ pid, err });
    //
    //    unreachable;
    //};
    // std.log.debug("pid {} required namespaces created", .{pid});

    std.log.debug("pid {} action action {any}", .{ pid, channelAction.Wait });
    pcomm.send(channelAction.Wait) catch {
        unreachable;
    };

    std.log.debug("pid {} waiting for action {any}", .{ pid, channelAction.Init });
    while (true) {
        switch (ccomm.receive() catch unreachable) {
            channelAction.Init => {
                std.log.debug("pid {} action {any} recevied", .{ pid, channelAction.Init });

                break;
            },
            else => {},
        }
    }

    mount.mountContainerRootFs(pid, rootfs) catch |err| {
        std.log.err("pid {} mount roofs: {any}", .{ pid, err });

        unreachable;
    };

    // setup hostname and domain name
    var hostname = DEFAULT_HOSTNAME;
    if (spec.hostname) |cnthostname| {
        hostname = cnthostname;
    }

    containerSetHostname(pid, hostname) catch |err| {
        std.log.err("pid {} set hostname error: {any}", .{ pid, err });

        unreachable;
    };

    if (spec.domainname) |cntdomainname| {
        containerSetDomainname(pid, cntdomainname) catch |err| {
            std.log.err("pid {} set domain name error: {any}", .{ pid, err });

            unreachable;
        };
    }

    // set working directory, uid and gid
    if (spec.process) |cprocess| {
        containerSetCwd(pid, cprocess.cwd) catch |err| {
            std.log.err("pid {} set working directory error: {any}", .{ pid, err });

            unreachable;
        };

        containerSetUidAndGid(pid, cprocess.user.uid, cprocess.user.gid) catch |err| {
            std.log.err("pid {} set uid and gid error: {any}", .{ pid, err });

            unreachable;
        };
    }

    // pivot root or chroot to rootfs
    if (noPivot) {
        filesystem.setChrootRootFs(pid, rootfs) catch |err| {
            std.log.err("pid {} chroot error: {any}", .{ pid, err });

            unreachable;
        };
    } else {
        filesystem.setPivotRootFs(pid, rootfs) catch |err| {
            std.log.err("pid {} pivot_root error: {any}", .{ pid, err });

            unreachable;
        };
    }

    // mount filesystems
    mount.mountContainersMounts(pid, spec) catch |err| {
        std.log.err("pid {}: {any}", .{ pid, err });

        unreachable;
    };

    // execute CMD and set ENV paths
    switch (linux.E.init(linux.execve("/bin/sh", &.{"sh"}, &.{""}))) {
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
