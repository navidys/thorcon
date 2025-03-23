const std = @import("std");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const ocispec = @import("ocispec");
const process = @import("process.zig");
const runtime = @import("runtime.zig");
const list = @import("list.zig");
const state = @import("state.zig");
const filesystem = @import("filesystem.zig");
const namespace = @import("namespace.zig");
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

    // TODO setup cgroup
    // TODO run hooks
    // TODO create NOTIFY SOCKET
    // TODO adjust oom if needed
    // TODO cleanup container (cgroup)

    const Args = std.meta.Tuple(&.{ []const u8, oci_runtime.Spec, bool });
    const args: Args = .{ containerState.rootfsDir, runtimeSpec, containerState.noPivot };

    var flags: u32 = 0;
    if (runtimeSpec.linux) |rlinux| {
        if (rlinux.namespaces) |namespaces| {
            flags = @intCast(namespace.getUnshareFlags(pid, namespaces));
        }
    }

    std.log.debug("pid {} process cloning", .{pid});
    const childPID = try process.clone(flags, runtime.prepareAndExecute, args);
    // TODO write PID file
    // write user map

    try writeMappings(pid, childPID, runtimeSpec);

    switch (posix.E.init(posix.waitpid(@intCast(childPID), 0).status)) {
        .SUCCESS => std.log.debug("pid {} child cloned process has terminated", .{pid}),
        else => |err| {
            std.log.err("pid {} unexpectedErrno: {any}", .{ pid, err });

            return errors.Error.ProcessCloneError;
        },
    }
}

pub fn writeMappings(pid: i32, tpid: usize, spec: oci_runtime.Spec) !void {
    if (utils.isRootLess()) {
        if (spec.linux) |rlinux| {
            if (rlinux.uidMappings) |uidmappings| {
                try namespace.writeUidMappings(pid, tpid, uidmappings);
            }

            // TODO gid mapping is not working ???
            // if (rlinux.gidMappings) |gidmappings| {
            //    try namespace.writeGidMappings(pid, tpid, gidmappings);
            //}
        }
    }
}
