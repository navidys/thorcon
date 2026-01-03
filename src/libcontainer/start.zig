const std = @import("std");
const errors = @import("errors.zig");
const channel = @import("channel.zig");
const state = @import("state.zig");
const filesystem = @import("filesystem.zig");
const cleanup = @import("cleanup.zig");
const channelAction = channel.PChannelAction;

pub fn startContainer(rootDir: ?[]const u8, name: []const u8) !void {
    if (name.len == 0) {
        return errors.Error.InvalidContainerName;
    }

    const rootdir = try filesystem.initRootPath(rootDir, null);
    const cntRootDir = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ rootdir, name });

    std.log.debug("container name {s}", .{name});
    std.log.debug("container root dir {s}", .{cntRootDir});

    try cleanup.refreshAllContainersState(rootdir);

    var cntstate = state.ContainerState.getContainerState(cntRootDir) catch |err| {
        if (err == std.fs.File.OpenError.FileNotFound) {
            return errors.Error.ContainerNotFound;
        }

        return err;
    };

    if (!cntstate.status.canStart()) {
        return errors.Error.ContainerInvalidStatus;
    }

    const cntPID = try cntstate.readPID();

    var comm = try channel.PChannel.initFromFDs(cntPID, cntstate.commReader, cntstate.commWriter);

    try comm.sendWithFD(channelAction.Start);

    try cntstate.setStatus(state.ContainerStatus.Running);
    try cntstate.writeStateFile();
}
