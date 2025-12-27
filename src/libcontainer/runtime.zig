const std = @import("std");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const ocispec = @import("ocispec");
const sched = @import("sched.zig");
const filesystem = @import("filesystem.zig");
const namespace = @import("namespace.zig");
pub const mount = @import("mount.zig");
const posix = std.posix;
const linux = std.os.linux;
const runtime = ocispec.runtime;

const uinstd = @cImport({
    @cInclude("unistd.h");
});

pub fn prepareAndExecute(rootfs: []const u8, spec: runtime.Spec, noPivot: bool) void {
    const pid = std.os.linux.getpid();

    namespace.setContainerNamespaces(pid, spec) catch |err| {
        std.log.debug("pid {} container name space: {any}", .{ pid, err });

        unreachable;
    };

    std.log.debug("pid {} required namespaces created", .{pid});

    // setup cgroup

    // setup hostname and domain name
    if (spec.hostname) |cnthostname| {
        containerSetHostname(cnthostname) catch |err| {
            std.log.err("pid {} unshare set hostname error: {any}", .{ pid, err });

            unreachable;
        };
    }

    if (spec.domainname) |cntdomainname| {
        containerSetDomainname(cntdomainname) catch |err| {
            std.log.err("pid {} unshare set domain name error: {any}", .{ pid, err });

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

    // set working directory
    if (spec.process) |cprocess| {
        containerSetCwd(cprocess.cwd) catch |err| {
            std.log.err("pid {} set working directory error: {any}", .{ pid, err });

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

fn containerSetCwd(path: []const u8) !void {
    const pid = std.os.linux.getpid();

    if (path.len != 0) {
        posix.chdir(path) catch |err| {
            std.log.err("pid {} container failed to changed directory to {s}: {any}", .{ pid, path, err });
            unreachable;
        };
    }
}

fn containerSetHostname(hostname: []const u8) !void {
    const pid = std.os.linux.getpid();

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

fn containerSetDomainname(domainname: []const u8) !void {
    const pid = std.os.linux.getpid();

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
