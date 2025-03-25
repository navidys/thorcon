const std = @import("std");
const clap = @import("clap");
const libcontainer = @import("libcontainer");

pub fn exec(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: anytype) !void {
    _ = main_args;

    var bundle_dir: []const u8 = undefined;
    var spec_file: []const u8 = undefined;
    var container_id: []const u8 = undefined;

    // The parameters for the subcommand.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help            display this help and exit.
        \\-b, --bundle <DIR>    path to the root of the bundle dir (default ".")
        \\-c, --config <PATH>   destination config file
        \\-n, --name <NAME>     name of the container instance 
        \\,--no-pivot do not use pivot_root
        \\,--no-new-keyring keep the same session key
        \\,--console-socket  <SOCK>  path to a socket that will receive the ptmx end of the tty
        \\,--pid-file <PATH> where to write the PID of the container
        \\,--preserve-fds <N> pass additional FDs to the container
        \\
    );

    const parsers = comptime .{
        .DIR = clap.parsers.string,
        .PATH = clap.parsers.string,
        .SOCK = clap.parsers.string,
        .N = clap.parsers.int(usize, 10),
        .NAME = clap.parsers.string,
    };

    // Here we pass the partially parsed argument iterator.
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, parsers, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};

        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return usage();

    if (res.args.bundle) |b| {
        bundle_dir = @constCast(b);
    } else {
        bundle_dir = ".";
    }

    if (res.args.config) |c| {
        spec_file = @constCast(c);
    } else {
        spec_file = "config.json";
    }

    if (res.args.name) |n| {
        container_id = @constCast(n);
    } else {
        return usage();
    }

    const createOpts = libcontainer.CreateOptions{
        .bundleDir = bundle_dir,
        .file = spec_file,
        .containerID = container_id,
    };

    try libcontainer.create(&createOpts);
}

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: create [OPTION...]\n\n", .{});
    try stdout.print("  -b, --bundle=DIR           {s}\n", .{"path to the root of the bundle dir (default \".\")"});
    try stdout.print("  -c, --config=PATH          {s}\n", .{"destination file"});
    try stdout.print("  -n, --name=NAME            {s}\n", .{"container name"});
    try stdout.print("  --no-pivot                 {s}\n", .{"do not use pivot_root"});
    try stdout.print("  --no-new-keyring           {s}\n", .{"keep the same session key"});
    try stdout.print("  --console-socket=SOCK      {s}\n", .{"path to a socket that will receive the ptmx end of the tty"});
    try stdout.print("  --pid-file=PATH            {s}\n", .{"where to write the PID of the container"});
    try stdout.print("  ---preserve-fds=N          {s}\n", .{"pass additional FDs to the container"});
    try stdout.print("  -h, --help                 {s}\n\n", .{"display help and exit"});
}
