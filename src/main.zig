const clap = @import("clap");
const std = @import("std");
const spec = @import("spec.zig");
const run = @import("run.zig");
const create = @import("create.zig");
const list = @import("list.zig");
const delete = @import("delete.zig");
const start = @import("start.zig");
const kill = @import("kill.zig");
const errors = @import("errors.zig");

const VERSION: []const u8 = "0.1.0-dev";

const subCommands = enum {
    help,
    spec,
    create,
    list,
    delete,
    start,
    run,
    kill,
};

const main_parsers = .{
    .command = clap.parsers.enumeration(subCommands),
    .PATH = clap.parsers.string,
};

// The parameters for `main`. Parameters for the subcommands are specified further down.
const main_params = clap.parseParamsComptime(
    \\-h, --help     Display this help and exit.
    \\-v, --version  Display version and exit.
    \\-r, --root <PATH> Root directory
    \\-d, --debug    Enable debug
    \\<command>
    \\
);

// To pass around arguments returned by clap, `clap.Result` and `clap.ResultEx` can be used to
// get the return type of `clap.parse` and `clap.parseEx`.
const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    var iter = try std.process.ArgIterator.initWithAllocator(gpa);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = gpa,

        // Terminate the parsing of arguments after parsing the first positional (0 is passed
        // here because parsed positionals are, like slices and arrays, indexed starting at 0).
        //
        // This will terminate the parsing after parsing the subcommand enum and leave `iter`
        // not fully consumed. It can then be reused to parse the arguments for subcommands.
        .terminating_positional = 0,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return usage();

    if (res.args.version != 0) {
        const stdout = std.io.getStdOut().writer();
        return stdout.print("version: {s}\n", .{VERSION});
    }

    const command = res.positionals[0] orelse return error.MissingCommand;
    switch (command) {
        .help => return usage(),
        .spec => try spec.exec(gpa, &iter, res),
        .run => try run.exec(gpa, &iter, res),
        .create => try create.exec(gpa, &iter, res),
        .delete => try delete.exec(gpa, &iter, res),
        .start => try start.exec(gpa, &iter, res),
        .list => try list.exec(gpa, &iter, res),
        .kill => try kill.exec(gpa, &iter, res),
    }
}

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: thorcon [OPTION...] COMMAND [OPTION...]\n\n", .{});
    try stdout.print("COMMANDS:\n", .{});
    try stdout.print("        create   - {s}\n", .{"create a container"});
    try stdout.print("        delete   - {s}\n", .{"remove definition for a container"});
    try stdout.print("        list     - {s}\n", .{"list known containers"});
    try stdout.print("        kill     - {s}\n", .{"send a signal to the container init process"});
    try stdout.print("        run      - {s}\n", .{"run a container"});
    try stdout.print("        spec     - {s}\n", .{"generate a configuration file"});
    try stdout.print("        start    - {s}\n", .{"start a container"});
    try stdout.print("      --root       {s}\n", .{"root directory"});
    try stdout.print("  -h, --help                \n", .{});
    try stdout.print("  -v, --version             \n", .{});
}
