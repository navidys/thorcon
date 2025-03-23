pub const spec = @import("spec.zig");
pub const create = @import("create.zig");

// These are our subcommands.
pub const SubCommands = enum {
    help,
    spec,
    create,
};
