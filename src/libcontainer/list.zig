const cntstate = @import("state.zig");
const filesystem = @import("filesystem.zig");

const std = @import("std");

pub const ContainerReport = struct {
    name: []const u8,
    pid: []const u8,
    bundle: []const u8,
    status: cntstate.ContainerStatus,
    created: []const u8,
};

pub fn ContainerExist(rootDir: ?[]const u8, name: []const u8) !bool {
    const rootdir = try filesystem.initRootPath(rootDir, null);
    const cntRootDir = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ rootdir, name });

    const cntRootDirStat = std.fs.cwd().statFile(cntRootDir) catch return false;
    if (cntRootDirStat.kind == .directory) {
        _ = try cntstate.ContainerState.initFromFile(cntRootDir);

        return true;
    }

    return false;
}

pub fn ListContainers(rootDir: ?[]const u8) ![]ContainerReport {
    const rootdir = try filesystem.initRootPath(rootDir, null);

    std.log.debug("root directory: {s}", .{rootdir});

    var root = try std.fs.cwd().openDir(rootdir, .{ .iterate = true });

    defer root.close();

    var containers = std.ArrayList(ContainerReport).init(std.heap.page_allocator);
    defer containers.deinit();

    var rootIter = root.iterate();
    while (try rootIter.next()) |dirContent| {
        switch (dirContent.kind) {
            .directory => {
                // load container state file
                const cntRootDir = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ rootdir, dirContent.name });
                const containerState = try cntstate.ContainerState.initFromFile(cntRootDir);
                const container = ContainerReport{
                    .name = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{dirContent.name}),
                    .bundle = containerState.bundleDir,
                    .created = containerState.created,
                    .status = containerState.status,
                    .pid = "",
                };

                // append to the list
                try containers.append(container);
            },
            else => std.log.debug("root runtime directory includes invalid content: {s}", .{dirContent.name}),
        }
    }

    return containers.toOwnedSlice();
}
