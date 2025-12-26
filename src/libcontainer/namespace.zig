const std = @import("std");
const ocispec = @import("ocispec");
const errors = @import("errors.zig");
const linux = std.os.linux;
const nstype = ocispec.runtime.LinuxNamespaceType;

pub fn setContainerNamespaces(pid: i32, spec: ocispec.runtime.Spec) !void {
    var nsflags: usize = 0;
    std.log.debug("pid {} create isolated namespace", .{pid});

    if (spec.linux) |slinux| {
        if (slinux.namespaces) |namespaces| {
            nsflags = getUnshareFlags(pid, namespaces);
        }
    }

    switch (linux.E.init(linux.unshare(nsflags))) {
        .SUCCESS => {},
        else => |err| {
            std.log.debug("pid {} namespace error: {any}", .{ pid, err });

            return errors.Error.ContainerNamespaceError;
        },
    }
}

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
