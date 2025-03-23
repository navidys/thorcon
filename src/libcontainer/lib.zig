const libspec = @import("spec.zig");
const libcreate = @import("create.zig");

pub const SpecOptions = libspec.SpecOptions;
pub const CreateOptions = libcreate.CreateOptions;

pub fn generateSpec(opts: *const libspec.SpecOptions) !void {
    return libspec.generateSpec(opts);
}

pub fn create(opts: *const libcreate.CreateOptions) !void {
    return libcreate.create(opts);
}
