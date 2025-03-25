const ocispec = @import("ocispec");
const std = @import("std");
const errors = @import("errors.zig");
const namespace = @import("namespace.zig");
const utils = @import("utils.zig");

const runtime = ocispec.runtime;

pub const UserNamespaceConfig = struct {
    /// Location of the newuidmap binary
    new_uid_map: ?[]const u8 = "/usr/bin/newuidmap",
    /// Location of the newgidmap binary
    new_gid_map: ?[]const u8 = "/usr/bin/newgidmap",
    /// Mappings for user ids
    uid_mappings: ?[]runtime.LinuxIdMapping,
    /// Mappings for group ids
    gid_mappings: ?[]runtime.LinuxIdMapping,
    // Info on the user namespaces
    user_namespace: ?runtime.LinuxNamespace,
    /// Is the container requested by a privileged user
    privileged: bool,

    pub fn init(spec: *const runtime.Spec) !?UserNamespaceConfig {
        std.debug.print("{any}\n", .{spec.linux});

        if (spec.linux) |linux| {
            const ns = namespace.Namespaces.init(linux.namespaces);
            const user_namespace = ns.get(runtime.LinuxNamespaceType.User);
            if (user_namespace) |user_ns| {
                if (user_ns.path == null) {
                    try validateSpecForNewUserns(linux);

                    if (spec.process) |process| {
                        if (process.user.additionalGids) |additioanl_gids| {
                            if (additioanl_gids.len > 0) {
                                if (utils.isRootLess())
                                    return errors.Error.SpecNamespaceUnprivilegedUser;
                            }
                        }
                    }

                    const ns_config = UserNamespaceConfig{
                        .uid_mappings = linux.uidMappings,
                        .gid_mappings = linux.gidMappings,
                        .user_namespace = user_ns,
                        .privileged = !utils.isRootLess(),
                    };

                    return ns_config;
                }
            } else {
                std.debug.print("container with out a new user namespace\n", .{});
            }
        }

        return null;
    }

    fn validateSpecForNewUserns(linux: runtime.Linux) !void {
        if (linux.gidMappings == null)
            return errors.Error.SpecNamespaecNoGidMappingsError;

        if (linux.uidMappings == null)
            return errors.Error.SpecNamespaceNoUidMappingsError;

        if (linux.uidMappings) |uid_mappings| {
            if (uid_mappings.len == 0)
                return errors.Error.SpecNamespaceNoUidMappingsError;
        } else {
            return errors.Error.SpecNamespaceNoUidMappingsError;
        }

        if (linux.gidMappings) |gid_mappings| {
            if (gid_mappings.len == 0)
                return errors.Error.SpecNamespaecNoGidMappingsError;
        } else {
            return errors.Error.SpecNamespaecNoGidMappingsError;
        }
    }
};

pub const UserNamespaceIDMapper = struct {
    path: []const u8,
};
