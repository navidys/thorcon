const std = @import("std");
const errors = @import("errors.zig");
const posix = std.posix;
const linux = std.os.linux;

pub fn setContainerMountPoints() !void {
    const pid = std.os.linux.getpid();

    const proc_path = try posix.toPosixPath("/proc");

    switch (linux.E.init(linux.mount("proc", &proc_path, "proc", 0, 0))) {
        .SUCCESS => {},
        else => |err| {
            std.log.debug("pid {} container proc mount error: {any}", .{ pid, err });
            return errors.Error.ContainerMountError;
        },
    }
}
