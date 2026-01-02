const std = @import("std");
const cntstate = @import("state.zig");
const cntstatus = cntstate.ContainerStatus;

pub fn refreshAllContainersState(rootDir: []const u8) !void {
    const gpa = std.heap.page_allocator;
    var root = try std.fs.cwd().openDir(rootDir, .{ .iterate = true });

    defer root.close();

    var rootIter = root.iterate();
    while (try rootIter.next()) |dirContent| {
        switch (dirContent.kind) {
            .directory => {
                // load container state file
                const cntRootDir = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ rootDir, dirContent.name });
                var containerState = cntstate.ContainerState.getContainerState(cntRootDir) catch continue;
                if (containerState.status != cntstatus.Undefined and containerState.status != cntstatus.Creating) {
                    const pidVal = containerState.readPID() catch 0;
                    if (pidVal != 0) {
                        const posixPID: std.posix.pid_t = @intCast(pidVal);
                        std.posix.kill(posixPID, 0) catch |err| {
                            if (err == error.ProcessNotFound) {
                                try containerState.setStatus(cntstatus.Stopped);
                                try containerState.writeStateFile();
                                // TODO cleanup mount points
                            }
                        };
                    }
                }
            },
            else => std.log.debug("root runtime directory includes invalid content: {s}", .{dirContent.name}),
        }
    }
}
