const utils = @import("utils.zig");
const spec = @import("spec.zig");
const container_builder = @import("container_builder.zig");
const state = @import("state.zig");
const errors = @import("errors.zig");
const rootpath = @import("rootpath.zig");
const config = @import("config.zig");
const userns = @import("userns.zig");
const namespace = @import("namespace.zig");

pub const SpecOptions = spec.SpecOptions;
pub const ContainerBuilder = container_builder.ContainerBuilder;
pub const ContainerState = state.ContainerState;
pub const ContainerStatus = state.ContainerStatus;
pub const Config = config.Config;
pub const UserNamespaceConfig = userns.UserNamespaceConfig;
pub const UserNamespaceIDMapper = userns.UserNamespaceIDMapper;
pub const UserNamespace = namespace.Namespaces;
pub const Error = errors.Error;

pub fn initRootPath(path: ?[]const u8) ![]const u8 {
    return try rootpath.initRootPath(path);
}

pub fn generateSpec(opts: *const spec.SpecOptions) !void {
    return spec.generateSpec(opts);
}

pub fn isRootless() bool {
    return utils.isRootless();
}
