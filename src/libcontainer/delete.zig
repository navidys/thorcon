const std = @import("std");
const cntstate = @import("state.zig");
const cntlist = @import("list.zig");
const errors = @import("errors.zig");
const utils = @import("utils.zig");
const filesystem = @import("filesystem.zig");

pub fn deleteContainer(rootDir: ?[]const u8, name: []const u8) !void {
    if (name.len == 0) {
        return errors.Error.InvalidContainerName;
    }

    const rootdir = try filesystem.initRootPath(rootDir, null);
    const cntRootDir = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ rootdir, name });

    std.log.debug("container name {s}", .{name});
    std.log.debug("container root dir {s}", .{cntRootDir});

    var cnts = cntstate.ContainerState.getContainerState(cntRootDir) catch |err| {
        if (err == std.fs.File.OpenError.FileNotFound) {
            return errors.Error.ContainerNotFound;
        }

        return err;
    };

    try cnts.lock();
    defer cnts.unlock() catch {};

    if (!cnts.status.canDelete()) {
        return errors.Error.ContainerInvalidStatus;
    }

    try utils.deleteDirAll(rootdir, name);
}
