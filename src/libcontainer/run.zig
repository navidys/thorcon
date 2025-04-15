const std = @import("std");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const ocispec = @import("ocispec");
const sched = @import("sched.zig");
const filesystem = @import("filesystem.zig");
const posix = std.posix;
const runtime = ocispec.runtime;

pub fn container_run(rootfs: []const u8, _: []const u8) !void {
    const Args = std.meta.Tuple(&.{[]const u8});
    const args: Args = .{rootfs};

    const child_pid = try sched.clone(run, args);

    switch (posix.E.init(posix.waitpid(@intCast(child_pid), 0).status)) {
        .SUCCESS => std.log.debug("child cloned process has terminated", .{}),
        else => |err| {
            std.log.debug("unexpectedErrno: {any}", .{err});
            unreachable;
        },
    }
}

fn run(rootfs: []const u8) void {
    sched.unshare();
    filesystem.mount_rootfs(rootfs);

    filesystem.set_root_fs(rootfs) catch |err| {
        std.log.debug("set rootfs error: {any}", .{err});
        unreachable;
    };

    std.time.sleep(10000000000);
}
