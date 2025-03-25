const std = @import("std");

const DEFAULT_ROOT_PATH = "/run/thorcon/";

pub fn initRootPath(path: ?[]const u8) ![]const u8 {
    const uid = std.os.linux.getuid();
    const gpa = std.heap.page_allocator;

    if (path) |p| {
        const rpath = try std.mem.concat(gpa, u8, &.{ p, "/" });

        try createDirAllWithMode(rpath);

        return rpath;
    }

    if (uid == 0) {
        try createDirAllWithMode(DEFAULT_ROOT_PATH);

        return DEFAULT_ROOT_PATH;
    }

    // rootless path
    // XDG_RUNTIME_DIR is set
    const runtime_dir = std.process.getEnvVarOwned(std.heap.page_allocator, "XDG_RUNTIME_DIR") catch {
        return try std.fmt.allocPrint(std.heap.page_allocator, "/tmp/thorcon/{d}/", .{uid});
    };

    const rundir = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/thorcon/", .{runtime_dir});

    try createDirAllWithMode(rundir);

    return rundir;
}

pub fn createDirAllWithMode(path: []const u8) !void {
    std.fs.cwd().makeDir(path) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    try dir.chmod(0o700);
}
