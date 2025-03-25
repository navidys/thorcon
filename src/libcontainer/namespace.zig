const std = @import("std");
const ocispec = @import("ocispec");
const errors = @import("errors.zig");

const runtime = ocispec.runtime;

pub const Namespaces = struct {
    namespaces: []runtime.LinuxNamespace,

    pub fn init(namespaces: ?[]runtime.LinuxNamespace) Namespaces {
        if (namespaces) |ns| {
            if (ns.len > 0)
                return Namespaces{
                    .namespaces = ns,
                };
        }

        return Namespaces{ .namespaces = &.{} };
    }

    pub fn get(self: @This(), nstype: runtime.LinuxNamespaceType) ?runtime.LinuxNamespace {
        for (self.namespaces) |ns| {
            if (ns.type == nstype) {
                return ns;
            }
        }

        return null;
    }
};
