pub const spec = @import("spec.zig");
pub const run = @import("run.zig");

// These are our subcommands.
pub const SubCommands = enum {
    help,
    spec,
    run,
};
