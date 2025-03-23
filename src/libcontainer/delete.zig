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
    std.log.debug("root directory: {s}", .{rootdir});

    if (!try cntlist.ContainerExist(rootDir, name)) {
        return errors.Error.ContainerNotFound;
    }

    const cntRootDir = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ rootdir, name });

    const state = cntstate.ContainerState.initFromFile(cntRootDir) catch {
        utils.deleteDirAll(rootdir, name) catch return;

        return;
    };

    if (state.status == cntstate.ContainerStatus.Running) {
        return errors.Error.ContainerInvalidState;
    }

    if (state.status == cntstate.ContainerStatus.Paused) {
        return errors.Error.ContainerInvalidState;
    }

    try utils.deleteDirAll(rootdir, name);
}
