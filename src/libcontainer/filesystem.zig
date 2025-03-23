const std = @import("std");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const posix = std.posix;
const linux = std.os.linux;

const DEFAULT_OLD_ROOT_PATH: []const u8 = ".oldroot";
const DEFAULT_ROOT_PATH: []const u8 = "/run/";
const DEFAULT_ROOTLESS_PATH: []const u8 = "/tmp/";
const DEFAULT_MODE = 0o700;

pub fn initRootPath(path: ?[]const u8, name: ?[]const u8) ![]const u8 {
    const uid = std.os.linux.getuid();
    const gpa = std.heap.page_allocator;

    var basePath = DEFAULT_ROOTLESS_PATH;

    if (path) |p| {
        basePath = p;
    } else {
        if (uid == 0) {
            basePath = try std.fmt.allocPrint(gpa, "{s}/thorcon/", .{DEFAULT_ROOT_PATH});
        } else {
            // rootless path
            // XDG_RUNTIME_DIR is set
            const xdgRuntimePath = std.process.getEnvVarOwned(gpa, "XDG_RUNTIME_DIR") catch {
                return DEFAULT_ROOTLESS_PATH;
            };

            basePath = try std.fmt.allocPrint(gpa, "{s}/thorcon/", .{xdgRuntimePath});
        }
    }

    if (name) |cname| {
        basePath = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ basePath, cname });
    }

    try utils.createDirAllWithMode(basePath, DEFAULT_MODE);

    return utils.canonicalPath(basePath);
}

pub fn setPivotRootFs(rootfs: []const u8) !void {
    const pid = std.os.linux.getpid();

    std.log.debug("pid {} rootfs using pivot_root", .{pid});

    const rootfs_dir = posix.toPosixPath(rootfs) catch |err| {
        std.log.debug("pid {} mount rootfs to posix path error: {any}", .{ pid, err });
        unreachable;
    };

    var old_root_fs = try std.mem.concat(std.heap.page_allocator, u8, &.{ rootfs, "/" });
    old_root_fs = try std.mem.concat(std.heap.page_allocator, u8, &.{ old_root_fs, DEFAULT_OLD_ROOT_PATH });

    std.log.debug("pid {} rootfs set: {s}", .{ pid, rootfs });
    std.log.debug("pid {} rootfs set old: {s}", .{ pid, old_root_fs });

    const old_rootfs_dir = posix.toPosixPath(old_root_fs) catch |err| {
        std.log.debug("pid {} mount rootfs to posix path error: {any}", .{ pid, err });
        unreachable;
    };

    mountRootFs(rootfs);

    try utils.createDirAllWithMode(old_root_fs, 0o777);
    switch (linux.E.init(linux.syscall2(linux.SYS.pivot_root, @intFromPtr(&rootfs_dir), @intFromPtr(&old_rootfs_dir)))) {
        .SUCCESS => {
            std.log.debug("pid {} perform chroot change directory to /", .{pid});
            posix.chdir("/") catch |err| {
                std.log.err("pid {} pivot_root failed to changed directory to /: {any}", .{ pid, err });
                unreachable;
            };
        },
        else => |err| {
            std.log.debug("pid {} pivot_root error: {any}", .{ pid, err });
            return errors.Error.PivotRootError;
        },
    }
}

pub fn setChrootRootFs(rootfs: []const u8) !void {
    const pid = std.os.linux.getpid();

    std.log.debug("pid {} rootfs using chroot", .{pid});
    std.log.debug("pid {} rootfs set: {s}", .{ pid, rootfs });

    const rootfs_dir = posix.toPosixPath(rootfs) catch |err| {
        std.log.debug("pid {} mount rootfs to posix path error: {any}", .{ pid, err });
        unreachable;
    };

    std.log.debug("pid {} performing chroot", .{pid});
    switch (linux.E.init(linux.chroot(&rootfs_dir))) {
        .SUCCESS => {
            std.log.debug("pid {} perform chroot change directory to /", .{pid});
            posix.chdir("/") catch |err| {
                std.log.err("pid {} chroot failed to changed directory to /: {any}", .{ pid, err });
                unreachable;
            };
        },
        else => |err| {
            std.log.debug("pid {} chroot error: {any}", .{ pid, err });
            return errors.Error.ChrootError;
        },
    }
}

pub fn mountRootFs(rootfs: []const u8) void {
    std.log.debug("mount bind rootfs: {s}", .{rootfs});

    const rootfs_dir = posix.toPosixPath(rootfs) catch |err| {
        std.log.debug("mount rootfs to posix path error: {any}", .{err});
        unreachable;
    };

    const mount_result = linux.mount(&rootfs_dir, &rootfs_dir, null, linux.MS.BIND, 0);
    switch (linux.E.init(mount_result)) {
        .SUCCESS => return,
        else => |err| {
            std.log.debug("mount rootfs error: {any}", .{err});
            unreachable;
        },
    }
}

pub fn umountHostRootfs() void {
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
