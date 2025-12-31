const std = @import("std");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const mount = @import("mount.zig");
const ocispec = @import("ocispec");
const posix = std.posix;
const linux = std.os.linux;

const DEFAULT_ROOT_PATH: []const u8 = "/run/";
const DEFAULT_ROOTLESS_PATH: []const u8 = "/tmp/";
const DEFAULT_OLD_ROOT_PATH: []const u8 = "/.oldroot";
pub const DEFAULT_MODE = 0o700;
pub const DEFAULT_CONTAINER_MODE = 0o750;
pub const DEFAULT_CONTAINER_PROC_MODE = 0o555;
pub const DEFAULT_CONTAINER_SYS_MODE = 0o555;
pub const DEFAULT_CONTAINER_SHM_MODE = 0o1777;
pub const DEFAULT_CONTAINER_TMPFS_MODE = 0o755;
pub const DEFAULT_CONTAINER_MQUEUE_MODE = 0o1777;
pub const DEFAULT_CONTAINER_DEVPTS_MODE = 0o755;

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

pub fn setPivotRootFs(pid: i32, rootfs: []const u8) !void {
    std.log.debug("pid {} rootfs using pivot_root", .{pid});

    const rootfs_dir = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{rootfs});

    const old_root_fs = try std.mem.concat(std.heap.page_allocator, u8, &.{ rootfs, DEFAULT_OLD_ROOT_PATH });

    std.log.debug("pid {} rootfs set: {s}", .{ pid, rootfs });
    std.log.debug("pid {} rootfs set old: {s}", .{ pid, old_root_fs });

    const old_rootfs_dir = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{old_root_fs});

    try utils.createDirAllWithMode(old_root_fs, 0o777);
    switch (linux.E.init(linux.syscall2(linux.SYS.pivot_root, @intFromPtr(&rootfs_dir), @intFromPtr(&old_rootfs_dir)))) {
        .SUCCESS => {
            std.log.debug("pid {} perform pivot_root change directory to /", .{pid});
            posix.chdir("/") catch |err| {
                std.log.err("pid {} pivot_root failed to changed directory to /: {any}", .{ pid, err });

                try mount.umountContainerRootfs(pid, DEFAULT_OLD_ROOT_PATH);

                return errors.Error.ContainerPivotRootError;
            };
        },
        else => |err| {
            std.log.debug("pid {} pivot_root error: {any}", .{ pid, err });

            return errors.Error.ContainerPivotRootError;
        },
    }
}

pub fn setChrootRootFs(pid: i32, rootfs: []const u8) !void {
    std.log.debug("pid {} rootfs using chroot", .{pid});
    std.log.debug("pid {} rootfs set: {s}", .{ pid, rootfs });

    const rootfs_dir = posix.toPosixPath(rootfs) catch |err| {
        std.log.debug("pid {} mount rootfs to posix path error: {any}", .{ pid, err });

        return errors.Error.ContainerChrootError;
    };

    std.log.debug("pid {} performing chroot", .{pid});
    switch (linux.E.init(linux.chroot(&rootfs_dir))) {
        .SUCCESS => {
            std.log.debug("pid {} perform chroot change directory to /", .{pid});
            posix.chdir("/") catch |err| {
                std.log.err("pid {} chroot failed to changed directory to /: {any}", .{ pid, err });

                return errors.Error.ContainerChrootError;
            };
        },
        else => |err| {
            std.log.debug("pid {} chroot error: {any}", .{ pid, err });

            return errors.Error.ContainerChrootError;
        },
    }
}
