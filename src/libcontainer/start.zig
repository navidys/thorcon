const std = @import("std");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const ocispec = @import("ocispec");
const sched = @import("sched.zig");
const runtime = @import("runtime.zig");
const list = @import("list.zig");
const state = @import("state.zig");
const filesystem = @import("filesystem.zig");
const posix = std.posix;
const linux = std.os.linux;
const oci_runtime = ocispec.runtime;

pub fn startContainer(rootDir: ?[]const u8, name: []const u8) !void {
    if (name.len == 0) {
        return errors.Error.InvalidContainerName;
    }

    if (!try list.ContainerExist(rootDir, name)) {
        return errors.Error.ContainerNotFound;
    }

    const rootdir = try filesystem.initRootPath(rootDir, name);
    std.log.debug("root directory: {s}", .{rootdir});

    const containerState = try state.ContainerState.initFromFile(rootdir);

    const pid = std.os.linux.getpid();
    std.log.debug("pid {} starting container", .{pid});

    const runtimeSpec = oci_runtime.Spec.initFromFile(containerState.specFile) catch |err| {
        std.log.err("pid {} failed to load runtime spec: {any}", .{ pid, err });

        return err;
    };

    const Args = std.meta.Tuple(&.{ []const u8, oci_runtime.Spec, bool });
    const args: Args = .{ containerState.rootfsDir, runtimeSpec, containerState.noPivot };

    const childPID = try sched.clone(runtime.prepareAndExecute, args);

    switch (posix.E.init(posix.waitpid(@intCast(childPID), 0).status)) {
        .SUCCESS => std.log.debug("pid {} child cloned process has terminated", .{pid}),
        else => |err| {
            std.log.err("pid {} unexpectedErrno: {any}", .{ pid, err });
            unreachable;
        },
    }
}
