const std = @import("std");
const clap = @import("clap");
const libcontainer = @import("libcontainer");

pub fn exec(_: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: anytype) !void {
    // _ = main_args;

    const params = [_]clap.Param(u8){
        .{
            .id = 'h',
            .names = .{ .short = 'h', .long = "help" },
        },
        .{
            .id = 'b',
            .names = .{ .short = 'b', .long = "bundle" },
            .takes_value = .one,
        },
        .{
            .id = 'f',
            .names = .{ .short = 'f', .long = "config" },
            .takes_value = .one,
        },
    };

    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = iter,
        .diagnostic = &diag,
    };

    var bundleDir: []const u8 = "";
    var spec: []const u8 = "";

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (parser.next() catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    }) |arg| {
        switch (arg.param.id) {
            'h' => return usage(),
            'b' => if (arg.value) |value| {
                bundleDir = value;
            },
            'f' => if (arg.value) |value| {
                spec = value;
            },

            else => return libcontainer.Error.InvalidContainerRunOptions,
        }
    }

    const cntmanager = try libcontainer.Manager.init("test", bundleDir, main_args.args.root, spec);
    try cntmanager.run();
}

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: create [OPTION...]\n\n", .{});
    try stdout.print("  -b, --bundle=DIR             {s}\n", .{"path to the root of the bundle dir (default \".\")"});
    try stdout.print("  -f, --config=PATH            {s}\n", .{"destination file"});
    try stdout.print("  -h, --help                   {s}\n\n", .{"display help and exit"});
}
