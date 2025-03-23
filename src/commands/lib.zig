pub const spec = @import("spec.zig");
pub const run = @import("run.zig");
pub const create = @import("create.zig");
pub const list = @import("list.zig");
pub const delete = @import("delete.zig");
pub const start = @import("start.zig");

// These are our subcommands.
pub const SubCommands = enum {
    help,
    spec,
    create,
    list,
    delete,
    start,
    run,
};
