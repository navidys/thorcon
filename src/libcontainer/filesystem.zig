const std = @import("std");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const posix = std.posix;
const linux = std.os.linux;

const DEFAULT_OLD_ROOT_PATH: []const u8 = ".oldroot";

pub fn set_root_fs(rootfs: []const u8) !void {
    var p_root_fs = try std.mem.concat(std.heap.page_allocator, u8, &.{ rootfs, "/" });
    p_root_fs = try std.mem.concat(std.heap.page_allocator, u8, &.{ p_root_fs, DEFAULT_OLD_ROOT_PATH });

    const rootfs_dir = posix.toPosixPath(rootfs) catch |err| {
        std.log.debug("mount rootfs to posix path error: {any}", .{err});
        unreachable;
    };

    const p_rootfs_dir = posix.toPosixPath(p_root_fs) catch |err| {
        std.log.debug("mount rootfs to posix path error: {any}", .{err});
        unreachable;
    };

    try utils.createDirAllWithMode(p_root_fs, 0o777);

    switch (linux.E.init(linux.syscall2(linux.SYS.pivot_root, @intFromPtr(&rootfs_dir), @intFromPtr(&p_rootfs_dir)))) {
        .SUCCESS => {},
        else => |err| {
            std.log.debug("pivot error: {any}", .{err});
            return errors.Error.PivotRootError;
        },
    }
}

pub fn mount_rootfs(rootfs: []const u8) void {
    std.log.debug("mount bind rootfs", .{});

    const rootfs_dir = posix.toPosixPath(rootfs) catch |err| {
        std.log.debug("mount rootfs to posix path error: {any}", .{err});
        unreachable;
    };

    const mount_result = linux.mount(&rootfs_dir, &rootfs_dir, null, linux.MS.BIND | linux.MS.REC, 0);
    switch (linux.E.init(mount_result)) {
        .SUCCESS => return,
        else => |err| {
            std.log.debug("mount rootfs error: {any}", .{err});
            unreachable;
        },
    }
}

pub fn umount_host_rootfs() void {
    std.log.debug("umount old rootfs", .{});

    const old_rootfs_dir = posix.toPosixPath(DEFAULT_OLD_ROOT_PATH) catch |err| {
        std.log.debug("umount old rootfs error: {any}", .{err});
        unreachable;
    };

    switch (linux.E.init(linux.umount2(old_rootfs_dir, linux.MNT.DETACH))) {
        .SUCCESS => std.log.debug("old rootfs to posix path", .{}),
        else => |err| {
            std.log.debug("umount old rootfs error: {any}", .{err});
            unreachable;
        },
    }
}
