const clap = @import("clap");
const std = @import("std");
const cmd = @import("commands/lib.zig");

const VERSION: []const u8 = "0.1.0-dev";

const main_parsers = .{
    .command = clap.parsers.enumeration(cmd.SubCommands),
    .PATH = clap.parsers.string,
};

// The parameters for `main`. Parameters for the subcommands are specified further down.
const main_params = clap.parseParamsComptime(
    \\-h, --help     Display this help and exit.
    \\-v, --version  Display version and exit.
    \\-r, --root <PATH> Root directory
    \\--systemd-cgroup use systemd cgroups
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

    var systemd_cgroup = false;

    // workaround for main args systemd-cgroup
    const margs_content = try std.fmt.allocPrint(std.heap.page_allocator, "{any}", .{res.args});
    const systemd_cgroup_enabled = std.mem.indexOf(u8, margs_content, ".systemd-cgroup = 1");
    if (systemd_cgroup_enabled) |enabled| {
        if (enabled >= 0)
            systemd_cgroup = true;
    }

    const command = res.positionals[0] orelse return error.MissingCommand;
    switch (command) {
        .help => return usage(),
        .spec => try cmd.spec.exec(gpa, &iter, res),
        .create => try cmd.create.exec(gpa, &iter, res, systemd_cgroup),
    }
}

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: thorcon [OPTION...] COMMAND [OPTION...]\n\n", .{});
    try stdout.print("COMMANDS:\n", .{});
    try stdout.print("        create   - {s}\n", .{"create a container"});
    try stdout.print("        delete   - {s}\n", .{"remove definition for a container"});
    try stdout.print("        exec     - {s}\n", .{"exec a command in a running container"});
    try stdout.print("        list     - {s}\n", .{"list known containers"});
    try stdout.print("        kill     - {s}\n", .{"send a signal to the container init process"});
    try stdout.print("        ps       - {s}\n", .{"show the processes in the container"});
    try stdout.print("        run      - {s}\n", .{"run a container"});
    try stdout.print("        spec     - {s}\n", .{"generate a configuration file"});
    try stdout.print("        start    - {s}\n", .{"start a container"});
    try stdout.print("        state    - {s}\n", .{"output the state of a container"});
    try stdout.print("        pause    - {s}\n", .{"unpause the processes in the container"});
    try stdout.print("        resume   - {s}\n\n", .{"generate a configuration file"});
    try stdout.print("      --root                {s}\n", .{"root directory"});
    try stdout.print("      --systemd-cgroup      {s}\n", .{"use systemd cgroups"});
    try stdout.print("  -h, --help                \n", .{});
    try stdout.print("  -v, --version             \n", .{});
}
