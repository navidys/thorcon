const std = @import("std");
const errors = @import("errors.zig");
const filesystem = @import("filesystem.zig");
const fs = std.fs;

pub fn isRootLess() bool {
    if (std.os.linux.getuid() == 0)
        return false;

    return true;
}

/// reads content of a given file path
pub fn readFileContent(file_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile(file_path, fs.File.OpenFlags{ .mode = .read_only });
    defer file.close();

    const file_size = try file.getEndPos();

    const buffer = try allocator.alloc(u8, file_size);

    _ = try file.readAll(buffer);

    return buffer;
}

pub fn writeFileContent(file_path: []const u8, content: []const u8) !void {
    const content_newline = try std.mem.concat(
        std.heap.page_allocator,
        u8,
        &.{ content, "\n" },
    );

    const file = try std.fs.cwd().createFile(file_path, fs.File.CreateFlags{ .read = false });

    defer file.close();

    _ = try file.writeAll(content_newline);
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

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
        std.log.err("openDir {s} {any}", .{ path, err });

        return err;
    };

    defer dir.close();

    try dir.chmod(mode);
}

pub fn createDirAll(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
}

pub fn deleteDirAll(path: []const u8, subPath: []const u8) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    return std.fs.Dir.deleteTree(dir, subPath);
}

pub fn toJsonString(value: anytype, pretty: bool) ![]const u8 {
    const allocator = std.heap.page_allocator;

    const jsonValue = switch (pretty) {
        true => try std.json.stringifyAlloc(
            allocator,
            value,
            .{ .emit_strings_as_arrays = false, .emit_null_optional_fields = false, .whitespace = .indent_4 },
        ),
        false => try std.json.stringifyAlloc(
            allocator,
            value,
            .{ .emit_strings_as_arrays = false, .emit_null_optional_fields = false },
        ),
    };

    return jsonValue;
}

pub fn getRootFSPath(bundledir: []const u8, rootfs: []const u8) ![]const u8 {
    var rootfsPath = rootfs;
    if (rootfsPath.len == 0)
        return errors.Error.SpecRootFsError;

    if (rootfsPath[rootfsPath.len - 1] != '/') {
        rootfsPath = try std.mem.concat(std.heap.page_allocator, u8, &.{ rootfsPath, "/" });
        rootfsPath = try std.mem.concat(std.heap.page_allocator, u8, &.{ "/", rootfsPath });
        rootfsPath = try std.mem.concat(std.heap.page_allocator, u8, &.{ bundledir, rootfsPath });
        rootfsPath = try canonicalPath(rootfsPath);
    }

    return rootfsPath;
}
