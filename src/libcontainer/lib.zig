const utils = @import("utils.zig");
const spec = @import("spec.zig");
const manager = @import("manager.zig");
const errors = @import("errors.zig");
const sched = @import("sched.zig");
const filesystem = @import("filesystem.zig");

pub const SpecOptions = spec.SpecOptions;
pub const Manager = manager.ContainerManager;
pub const Error = errors.Error;

pub fn generateSpec(opts: *const spec.SpecOptions) !void {
    return spec.generateSpec(opts);
}

pub fn isRootless() bool {
    return utils.isRootless();
}
