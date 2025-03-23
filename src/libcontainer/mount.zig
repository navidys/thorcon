const std = @import("std");
const ocispec = @import("ocispec");
const utils = @import("utils.zig");
const filesystem = @import("filesystem.zig");
const errors = @import("errors.zig");
const posix = std.posix;
const linux = std.os.linux;

const mountInfo = struct {
    source: [:0]u8,
    dest: [posix.PATH_MAX - 1:0]u8,
    destZ: []const u8,
    fstype: [:0]u8,
    options: mountOptions,
};

const mountOptions = struct {
    flags: u32,
    data: []u8,
};

pub fn mountContainersMounts(pid: i32, spec: ocispec.runtime.Spec) !void {
    // TODO mount cgroup
    std.log.debug("pid {} setting container mount points", .{pid});

    const gpa = std.heap.page_allocator;

    //std.log.debug("pid {} mounting container / mount point", .{pid});
    // const rootPath = try posix.toPosixPath("/");
    // const rootSource = try std.fmt.allocPrintZ(gpa, "none", .{});

    // (linux.E.init(linux.mount(rootSource, &rootPath, null, linux.MS.REC | linux.MS.PRIVATE, 0))) {
    //    .SUCCESS => {},
    //    else => |err| {
    //        std.log.debug("pid {} container mount / error: {any}", .{ pid, err });
    //        return errors.Error.ContainerMountError;
    //    },
    // }

    var cntInitMounts = std.ArrayList(mountInfo).init(gpa);
    var cntPostInitMounts = std.ArrayList(mountInfo).init(gpa);

    defer cntPostInitMounts.deinit();
    defer cntInitMounts.deinit();

    if (spec.mounts) |mountPoints| {
        for (mountPoints) |mountPoint| {
            // TODO create directotories
            // TODO check if type is bind then create parent directory
            const minfo = try prepareMountPoint(pid, mountPoint);

            if (std.mem.eql(u8, mountPoint.destination, "/proc")) {
                try cntInitMounts.append(minfo);

                continue;
            }

            if (std.mem.eql(u8, mountPoint.destination, "/sys")) {
                try cntInitMounts.append(minfo);

                continue;
            }

            if (std.mem.eql(u8, mountPoint.destination, "/dev")) {
                try cntInitMounts.append(minfo);

                continue;
            }

            try cntPostInitMounts.append(minfo);
        }
    }

    // init mounts
    for (cntInitMounts.items) |minfo| {
        var mdataPtr: usize = 0;
        if (minfo.options.data.len != 0) {
            const mdata = try std.fmt.allocPrintZ(gpa, "{s}", .{minfo.options.data});
            mdataPtr = @intFromPtr(&mdata);
        }

        const destPerm = getContainerMountPointMode(minfo.destZ);

        try utils.createDirAllWithMode(minfo.destZ, destPerm);

        switch (linux.E.init(linux.mount(minfo.source, &minfo.dest, minfo.fstype, minfo.options.flags, mdataPtr))) {
            .SUCCESS => {},
            else => |err| {
                std.log.debug("pid {} container mount error: {any} {s}", .{ pid, err, minfo.dest });

                return errors.Error.ContainerMountError;
            },
        }
    }

    // post init mounts
    for (cntPostInitMounts.items) |minfo| {
        var mdataPtr: usize = 0;
        if (minfo.options.data.len != 0) {
            const mdata = try std.fmt.allocPrintZ(gpa, "{s}", .{minfo.options.data});
            mdataPtr = @intFromPtr(&mdata);
        }

        const destPerm = getContainerMountPointMode(minfo.destZ);

        try utils.createDirAllWithMode(minfo.destZ, destPerm);

        switch (linux.E.init(linux.mount(minfo.source, &minfo.dest, minfo.fstype, minfo.options.flags, mdataPtr))) {
            .SUCCESS => {},
            else => |err| {
                std.log.debug("pid {} container mount error: {any} {s}", .{ pid, err, minfo.dest });

                return errors.Error.ContainerMountError;
            },
        }
    }
}

pub fn mountContainerRootFs(pid: i32, rootfs: []const u8) !void {
    std.log.debug("pid {} mount bind rootfs: {s}", .{ pid, rootfs });

    const rootfs_dir = try posix.toPosixPath(rootfs);
    const rootfs_source = try std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{rootfs});

    const mount_result = linux.mount(rootfs_source, &rootfs_dir, null, linux.MS.BIND | linux.MS.PRIVATE | linux.MS.REC, 0);
    switch (linux.E.init(mount_result)) {
        .SUCCESS => return,
        else => |err| {
            std.log.debug("pid {} mount rootfs error: {any}", .{ pid, err });

            return errors.Error.ContainerRootfsMountError;
        },
    }
}

pub fn umountContainerRootfs(pid: i32, path: []const u8) !void {
    std.log.debug("pid {} umount rootfs {s}", .{ pid, path });

    const old_rootfs_dir = try posix.toPosixPath(path);

    switch (linux.E.init(linux.umount2(&old_rootfs_dir, linux.MNT.DETACH))) {
        .SUCCESS => {},
        else => |err| {
            std.log.debug("pid {} umount old rootfs error: {any}", .{ pid, err });

            return errors.Error.ContainerRootfsUmountError;
        },
    }
}

fn prepareMountPoint(pid: i32, mount: ocispec.runtime.Mount) !mountInfo {
    const pga = std.heap.page_allocator;

    std.log.debug("pid {} prepare mount point {s}", .{ pid, mount.destination });

    const mountPath = try posix.toPosixPath(mount.destination);

    var mountSource = try std.fmt.allocPrintZ(pga, "none", .{});
    var mountType = try std.fmt.allocPrintZ(pga, "", .{});

    if (mount.source) |src| {
        mountSource = try std.fmt.allocPrintZ(pga, "{s}", .{src});
    }

    if (mount.type) |mtype| {
        mountType = try std.fmt.allocPrintZ(pga, "{s}", .{mtype});
    }

    const mOptions = try getMountFlagsAndData(mount.options);

    const mountInformation = mountInfo{
        .source = mountSource,
        .dest = mountPath,
        .destZ = mount.destination,
        .fstype = mountType,
        .options = mOptions,
    };

    return mountInformation;
}

fn getMountFlagsAndData(options: ?[][]const u8) !mountOptions {
    // TODO mount data is not parsed correctly

    var result = mountOptions{
        .flags = 0,
        .data = try std.fmt.allocPrint(std.heap.page_allocator, "", .{}),
    };

    if (options) |moptions| {
        for (moptions) |mopt| {
            if (std.mem.eql(u8, mopt, "nosuid")) {
                if (result.flags == 0) {
                    result.flags = linux.MS.NOSUID;
                } else {
                    result.flags = result.flags | linux.MS.NOSUID;
                }

                continue;
            }

            if (std.mem.eql(u8, mopt, "noexec")) {
                if (result.flags == 0) {
                    result.flags = linux.MS.NOEXEC;
                } else {
                    result.flags = result.flags | linux.MS.NOEXEC;
                }

                continue;
            }

            if (std.mem.eql(u8, mopt, "nodev")) {
                if (result.flags == 0) {
                    result.flags = linux.MS.NODEV;
                } else {
                    result.flags = result.flags | linux.MS.NODEV;
                }

                continue;
            }

            if (std.mem.eql(u8, mopt, "relatime")) {
                if (result.flags == 0) {
                    result.flags = linux.MS.RELATIME;
                } else {
                    result.flags = result.flags | linux.MS.RELATIME;
                }

                continue;
            }

            if (std.mem.eql(u8, mopt, "ro")) {
                if (result.flags == 0) {
                    result.flags = linux.MS.RDONLY;
                } else {
                    result.flags = result.flags | linux.MS.RDONLY;
                }

                continue;
            }

            if (std.mem.eql(u8, mopt, "noatime")) {
                if (result.flags == 0) {
                    result.flags = linux.MS.NOATIME;
                } else {
                    result.flags = result.flags | linux.MS.NOATIME;
                }

                continue;
            }

            if (std.mem.eql(u8, mopt, "strictatime")) {
                if (result.flags == 0) {
                    result.flags = linux.MS.STRICTATIME;
                } else {
                    result.flags = result.flags | linux.MS.STRICTATIME;
                }

                continue;
            }

            if (result.data.len == 0) {
                result.data = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{mopt});
            } else {
                result.data = try std.fmt.allocPrint(std.heap.page_allocator, "{s},{s}", .{ result.data, mopt });
            }
        }
    }

    return result;
}

fn getContainerMountPointMode(dest: []const u8) std.fs.File.Mode {
    if (std.mem.eql(u8, dest, "/proc")) {
        return filesystem.DEFAULT_CONTAINER_PROC_MODE;
    }

    if (std.mem.eql(u8, dest, "/sys")) {
        return filesystem.DEFAULT_CONTAINER_SYS_MODE;
    }

    if (std.mem.eql(u8, dest, "/dev/shm")) {
        return filesystem.DEFAULT_CONTAINER_SHM_MODE;
    }

    if (std.mem.eql(u8, dest, "/dev/mqueue")) {
        return filesystem.DEFAULT_CONTAINER_MQUEUE_MODE;
    }

    if (std.mem.eql(u8, dest, "/dev/pts")) {
        return filesystem.DEFAULT_CONTAINER_DEVPTS_MODE;
    }

    if (std.mem.eql(u8, dest, "/dev")) {
        return filesystem.DEFAULT_CONTAINER_TMPFS_MODE;
    }

    return filesystem.DEFAULT_MODE;
}
