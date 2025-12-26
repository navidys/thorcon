const std = @import("std");
const ocispec = @import("ocispec");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const posix = std.posix;
const linux = std.os.linux;

pub fn setContainerMountPoints(pid: i32, spec: ocispec.runtime.Spec) !void {
    std.log.debug("pid {} setting container mount points", .{pid});

    if (spec.mounts) |mountPoints| {
        for (mountPoints) |mountPoint| {
            std.log.debug(
                "pid {} mount {s}",
                .{ pid, mountPoint.destination },
            );

            const mountPath = try posix.toPosixPath(mountPoint.destination);
            var mountSource = try std.fmt.allocPrintZ(std.heap.page_allocator, "none", .{});
            var mountType = try std.fmt.allocPrintZ(std.heap.page_allocator, "", .{});

            if (mountPoint.source) |src| {
                mountSource = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{src});
            }

            if (mountPoint.type) |mtype| {
                mountType = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{mtype});
            }

            // TODO create directotories
            // TODO check if type is bind then create parent directory

            std.log.debug("pid {} mkdir {s}", .{ pid, mountPoint.destination });
            try utils.createDirAll(mountPoint.destination);

            switch (linux.E.init(linux.mount(mountSource, &mountPath, mountType, 0, 0))) {
                .SUCCESS => {},
                else => |err| {
                    std.log.debug("pid {} container mount error: {any}", .{ pid, err });
                    return errors.Error.ContainerMountError;
                },
            }
        }
    }
}
