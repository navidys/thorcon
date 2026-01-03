const cntstate = @import("state.zig");
const filesystem = @import("filesystem.zig");
const errors = @import("errors.zig");
const cleanup = @import("cleanup.zig");
const std = @import("std");

pub const ContainerReport = struct {
    name: []const u8,
    pid: []const u8,
    bundle: []const u8,
    status: cntstate.ContainerStatus,
    created: []const u8,
};

pub fn ListContainers(rootDir: ?[]const u8) ![]ContainerReport {
    const gpa = std.heap.page_allocator;
    const rootdir = try filesystem.initRootPath(rootDir, null);

    std.log.debug("root directory: {s}", .{rootdir});

    try cleanup.refreshAllContainersState(rootdir);

    var root = try std.fs.cwd().openDir(rootdir, .{ .iterate = true });

    defer root.close();

    var containers = std.ArrayList(ContainerReport).init(gpa);
    defer containers.deinit();

    var rootIter = root.iterate();
    while (try rootIter.next()) |dirContent| {
        switch (dirContent.kind) {
            .directory => {
                // load container state file
                const cntRootDir = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ rootdir, dirContent.name });
                const containerState = cntstate.ContainerState.initFromRootDir(cntRootDir) catch continue;
                if (containerState.status != cntstate.ContainerStatus.Undefined) {
                    var pid: []const u8 = "";
                    const pidVal = containerState.readPID() catch 0;
                    if (pidVal != 0) {
                        pid = try std.fmt.allocPrint(gpa, "{d}", .{pidVal});
                    }

                    const container = ContainerReport{
                        .name = try std.fmt.allocPrint(gpa, "{s}", .{dirContent.name}),
                        .bundle = containerState.bundleDir,
                        .created = containerState.created,
                        .status = containerState.status,
                        .pid = pid,
                    };

                    // append to the list
                    try containers.append(container);
                }
            },
            else => std.log.debug("root runtime directory includes invalid content: {s}", .{dirContent.name}),
        }
    }

    return containers.toOwnedSlice();
}
