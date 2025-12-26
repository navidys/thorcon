const std = @import("std");
const ocispec = @import("ocispec");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const posix = std.posix;
const linux = std.os.linux;

pub fn setContainerMountPoints(pid: i32, spec: ocispec.runtime.Spec) !void {
    // TODO mount cgroup
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
            var mountFlags: u32 = 0;
            var mountData = try std.fmt.allocPrint(std.heap.page_allocator, "", .{});

            if (mountPoint.source) |src| {
                mountSource = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{src});
            }

            if (mountPoint.type) |mtype| {
                mountType = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{mtype});
            }

            if (mountPoint.options) |options| {
                for (options) |mopt| {
                    if (std.mem.eql(u8, mopt, "nosuid")) {
                        if (mountFlags == 0) {
                            mountFlags = linux.MS.NOSUID;
                        } else {
                            mountFlags = mountFlags | linux.MS.NOSUID;
                        }

                        continue;
                    }

                    if (std.mem.eql(u8, mopt, "noexec")) {
                        if (mountFlags == 0) {
                            mountFlags = linux.MS.NOEXEC;
                        } else {
                            mountFlags = mountFlags | linux.MS.NOEXEC;
                        }

                        continue;
                    }

                    if (std.mem.eql(u8, mopt, "nodev")) {
                        if (mountFlags == 0) {
                            mountFlags = linux.MS.NODEV;
                        } else {
                            mountFlags = mountFlags | linux.MS.NODEV;
                        }

                        continue;
                    }

                    if (std.mem.eql(u8, mopt, "relatime")) {
                        if (mountFlags == 0) {
                            mountFlags = linux.MS.RELATIME;
                        } else {
                            mountFlags = mountFlags | linux.MS.RELATIME;
                        }

                        continue;
                    }

                    if (std.mem.eql(u8, mopt, "ro")) {
                        if (mountFlags == 0) {
                            mountFlags = linux.MS.RDONLY;
                        } else {
                            mountFlags = mountFlags | linux.MS.RDONLY;
                        }

                        continue;
                    }

                    if (std.mem.eql(u8, mopt, "noatime")) {
                        if (mountFlags == 0) {
                            mountFlags = linux.MS.NOATIME;
                        } else {
                            mountFlags = mountFlags | linux.MS.NOATIME;
                        }

                        continue;
                    }

                    if (std.mem.eql(u8, mopt, "strictatime")) {
                        if (mountFlags == 0) {
                            mountFlags = linux.MS.STRICTATIME;
                        } else {
                            mountFlags = mountFlags | linux.MS.STRICTATIME;
                        }

                        continue;
                    }

                    if (mountData.len == 0) {
                        mountData = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{mopt});
                    } else {
                        mountData = try std.fmt.allocPrint(std.heap.page_allocator, "{s},{s}", .{ mountData, mopt });
                    }
                }
            }

            // TODO create directotories
            // TODO check if type is bind then create parent directory
            try utils.createDirAll(mountPoint.destination);

            // TODO mount data is not parsed correctly

            if (mountData.len != 0) {
                const mountD = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{mountData});
                switch (linux.E.init(linux.mount(mountSource, &mountPath, mountType, mountFlags, @intFromPtr(&mountD)))) {
                    .SUCCESS => {},
                    else => |err| {
                        std.log.debug("pid {} container mount error: {any}", .{ pid, err });
                        return errors.Error.ContainerMountError;
                    },
                }
            } else {
                switch (linux.E.init(linux.mount(mountSource, &mountPath, mountType, mountFlags, 0))) {
                    .SUCCESS => {},
                    else => |err| {
                        std.log.debug("pid {} container mount error: {any}", .{ pid, err });
                        return errors.Error.ContainerMountError;
                    },
                }
            }
        }
    }
}
