const std = @import("std");
const linux = std.os.linux;
const errors = @import("errors.zig");

pub fn setContainerNamespaces(pid: i32) !void {
    std.log.debug("pid {} create isolated namespace", .{pid});

    // TODO read flags from spec
    const unshare_flags = linux.CLONE.NEWNS | linux.CLONE.NEWCGROUP | linux.CLONE.NEWNET | linux.CLONE.NEWUTS | linux.CLONE.NEWPID | linux.CLONE.NEWIPC;
    switch (linux.E.init(linux.unshare(unshare_flags))) {
        .SUCCESS => {},
        else => |err| {
            std.log.debug("pid {} namespace error: {any}", .{ pid, err });

            return errors.Error.ContainerNamespaceError;
        },
    }
}
