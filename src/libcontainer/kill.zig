const std = @import("std");
const errors = @import("errors.zig");
const list = @import("list.zig");
const filesystem = @import("filesystem.zig");
const state = @import("state.zig");
const cleanup = @import("cleanup.zig");

pub fn killContainer(rootDir: ?[]const u8, name: []const u8) !void {
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

    if (!cntstate.status.canKill()) {
        return errors.Error.ContainerInvalidStatus;
    }

    const cntPID = try cntstate.readPID();
    const posixPID: std.posix.pid_t = @intCast(cntPID);

    std.log.debug("container PID: {d}", .{cntPID});

    try std.posix.kill(posixPID, std.posix.SIG.KILL);

    try cntstate.setStatus(state.ContainerStatus.Stopped);
    try cntstate.writeStateFile();
}
