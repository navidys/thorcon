const std = @import("std");
const clap = @import("clap");
const libcontainer = @import("libcontainer");

pub fn exec(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: anytype) !void {
    _ = main_args;

    var bundle_dir: []const u8 = undefined;
    var spec_file: []const u8 = undefined;
    var rootless = false;

    // The parameters for the subcommand.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help           display this help and exit.
        \\-b, --bundle <DIR>   path to the root of the bundle dir (default ".")
        \\-c, --config <PATH>  destination config file
        \\    --rootless       spec for the rootless case
        \\
    );

    const parsers = comptime .{
        .DIR = clap.parsers.string,
        .PATH = clap.parsers.string,
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

    if (res.args.rootless != 0)
        rootless = true;

    const secp_opts = libcontainer.spec.SpecOptions{
        .rootless = rootless,
        .bundleDir = bundle_dir,
        .file = spec_file,
    };

    try libcontainer.spec.generateSpec(&secp_opts);
}

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: spec [OPTION...]\n\n", .{});
    try stdout.print("  -b, --bundle=DIR           {s}\n", .{"path to the root of the bundle dir (default \".\")"});
    try stdout.print("  -c, --config=PATH          {s}\n", .{"destination file"});
    try stdout.print("      --rootless             {s}\n", .{"spec for the rootless case"});
    try stdout.print("  -h, --help                 {s}\n\n", .{"display help and exit"});
}
