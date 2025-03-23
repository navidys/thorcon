const std = @import("std");
const utils = @import("utils.zig");

const DEFAULT_ROOT_PATH = "/run/thorcon";
const DEFAULT_MODE = 0o700;

pub fn initRootPath(path: ?[]const u8) ![]const u8 {
    const uid = std.os.linux.getuid();
    const gpa = std.heap.page_allocator;

    if (path) |p| {
        const rpath = try std.mem.concat(gpa, u8, &.{ p, "/" });

        try utils.createDirAllWithMode(rpath, DEFAULT_MODE);

        return utils.canonicalPath(rpath);
    }

    if (uid == 0) {
        try utils.createDirAllWithMode(DEFAULT_ROOT_PATH, DEFAULT_MODE);

        return DEFAULT_ROOT_PATH;
    }

    // rootless path
    // XDG_RUNTIME_DIR is set
    const runtime_dir = std.process.getEnvVarOwned(std.heap.page_allocator, "XDG_RUNTIME_DIR") catch {
        return try std.fmt.allocPrint(std.heap.page_allocator, "/tmp/thorcon/{d}", .{uid});
    };

    const rundir = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/thorcon", .{runtime_dir});

    try utils.createDirAllWithMode(rundir, DEFAULT_MODE);

    return utils.canonicalPath(rundir);
}
