const std = @import("std");
const clap = @import("clap");
const libcontainer = @import("libcontainer");
const errors = @import("errors.zig");

pub fn exec(_: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: anytype) !void {
    // _ = main_args;

    const params = [_]clap.Param(u8){
        .{
            .id = 'h',
            .names = .{ .short = 'h', .long = "help" },
        },
        .{
            .id = 'n',
            .takes_value = .one,
        },
    };

    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = iter,
        .diagnostic = &diag,
    };

    var containerName: []const u8 = "";

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (parser.next() catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    }) |arg| {
        switch (arg.param.id) {
            'h' => return usage(),
            'n' => if (arg.value) |value| {
                containerName = value;
            },
            else => return errors.Error.InvalidContainerStartOptions,
        }
    }

    try libcontainer.start.startContainer(main_args.args.root, containerName);
}

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: start [OPTION...] CONTAINER\n\n", .{});
    try stdout.print("  -h, --help                   {s}\n\n", .{"display help and exit"});
}
