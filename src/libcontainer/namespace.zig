const std = @import("std");
const ocispec = @import("ocispec");
const errors = @import("errors.zig");
const utils = @import("utils.zig");
const linux = std.os.linux;
const nstype = ocispec.runtime.LinuxNamespaceType;

//pub fn setContainerNamespaces(pid: i32, spec: ocispec.runtime.Spec) !void {
//    var nsflags: usize = 0;
//    std.log.debug("pid {} create isolated namespace", .{pid});
//
//    if (spec.linux) |slinux| {
//        if (slinux.namespaces) |namespaces| {
//            nsflags = getUnshareFlags(pid, namespaces);
//       }
//    }
//
//    switch (linux.E.init(linux.unshare(nsflags))) {
//        .SUCCESS => {},
//        else => |err| {
//            std.log.debug("pid {} namespace error: {any}", .{ pid, err });

//            return errors.Error.ContainerNamespaceError;
//        },
//    }
//}

pub fn getUnshareFlags(pid: i32, namespaces: []ocispec.runtime.LinuxNamespace) usize {
    var nsflags: usize = 0;

    for (namespaces) |ns| {
        std.log.debug("pid {} {}", .{ pid, ns.type });
        switch (ns.type) {
            nstype.Cgroup => {
                if (nsflags == 0) {
                    nsflags = linux.CLONE.NEWCGROUP;
                } else {
                    nsflags = nsflags | linux.CLONE.NEWCGROUP;
                }
            },
            nstype.Ipc => {
                if (nsflags == 0) {
                    nsflags = linux.CLONE.NEWIPC;
                } else {
                    nsflags = nsflags | linux.CLONE.NEWIPC;
                }
            },
            nstype.Mount => {
                if (nsflags == 0) {
                    nsflags = linux.CLONE.NEWNS;
                } else {
                    nsflags = nsflags | linux.CLONE.NEWNS;
                }
            },
            nstype.Network => {
                if (nsflags == 0) {
                    nsflags = linux.CLONE.NEWNET;
                } else {
                    nsflags = nsflags | linux.CLONE.NEWNET;
                }
            },
            nstype.Pid => {
                if (nsflags == 0) {
                    nsflags = linux.CLONE.NEWPID;
                } else {
                    nsflags = nsflags | linux.CLONE.NEWPID;
                }
            },
            nstype.Time => {
                if (nsflags == 0) {
                    nsflags = linux.CLONE.NEWTIME;
                } else {
                    nsflags = nsflags | linux.CLONE.NEWTIME;
                }
            },
            nstype.User => {
                if (nsflags == 0) {
                    nsflags = linux.CLONE.NEWUSER;
                } else {
                    nsflags = nsflags | linux.CLONE.NEWUSER;
                }
            },
            nstype.Uts => {
                if (nsflags == 0) {
                    nsflags = linux.CLONE.NEWUTS;
                } else {
                    nsflags = nsflags | linux.CLONE.NEWUTS;
                }
            },
        }
    }

    return nsflags;
}

pub fn writeUidMappings(pid: i32, tpid: usize, mappings: []ocispec.runtime.LinuxIdMapping) !void {
    std.log.debug("pid {} writing uid mapping for pid {}", .{ pid, tpid });

    const gp = std.heap.page_allocator;

    var uidMappings: []u8 = "";

    for (mappings) |uidMap| {
        const mappingRow = try std.fmt.allocPrint(
            gp,
            "    {any}    {any}    {any}",
            .{ uidMap.containerID, uidMap.hostID, uidMap.size },
        );

        if (std.mem.eql(u8, uidMappings, "")) {
            uidMappings = mappingRow;

            continue;
        }

        uidMappings = try std.fmt.allocPrint(
            gp,
            "{s}\n    {any}    {any}    {any}",
            .{ uidMappings, uidMap.containerID, uidMap.hostID, uidMap.size },
        );
    }

    const filePath = try std.fmt.allocPrint(gp, "/proc/{}/uid_map", .{tpid});

    try utils.writeFileContent(filePath, uidMappings);
}

pub fn writeGidMappings(pid: i32, tpid: usize, mappings: []ocispec.runtime.LinuxIdMapping) !void {
    std.log.debug("pid {} writing gid mapping for pid {}", .{ pid, tpid });

    const gp = std.heap.page_allocator;

    var gidMappings: []u8 = "";

    for (mappings) |gidMap| {
        const mappingRow = try std.fmt.allocPrint(
            gp,
            "    {any}    {any}    {any}",
            .{ gidMap.containerID, gidMap.hostID, gidMap.size },
        );

        if (std.mem.eql(u8, gidMappings, "")) {
            gidMappings = mappingRow;

            continue;
        }

        gidMappings = try std.fmt.allocPrint(
            gp,
            "{s}\n    {any}    {any}    {any}",
            .{ gidMappings, gidMap.containerID, gidMap.hostID, gidMap.size },
        );
    }

    const filePath = try std.fmt.allocPrint(gp, "/proc/{}/gid_map", .{tpid});

    try utils.writeFileContent(filePath, gidMappings);
}
