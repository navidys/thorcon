const std = @import("std");

pub fn isRootLess() bool {
    if (std.os.linux.getuid() == 0)
        return false;

    return true;
}

pub fn canonicalPath(path: []const u8) ![]const u8 {
    const allocator = std.heap.page_allocator;

    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    const absolute_path = try std.fs.path.resolve(allocator, &.{
        cwd_path,
        path,
    });

    return absolute_path;
}

pub fn createDirAllWithMode(path: []const u8, mode: std.fs.File.Mode) !void {
    std.fs.cwd().makeDir(path) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    try dir.chmod(mode);
}
