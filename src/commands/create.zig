const std = @import("std");
const clap = @import("clap");
const libcontainer = @import("libcontainer");

pub fn exec(_: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: anytype, systemd_cgroup: bool) !void {
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
        .{
            .id = 'n',
            .names = .{ .short = 'n', .long = "name" },
            .takes_value = .one,
        },
        .{
            .id = 'u',
            .names = .{ .long = "no-pivot" },
        },
        .{
            .id = 'w',
            .names = .{ .long = "no-new-keyring" },
        },
        .{
            .id = 'x',
            .names = .{ .long = "console-socket" },
            .takes_value = .one,
        },
        .{
            .id = 'y',
            .names = .{ .long = "pid-file" },
            .takes_value = .one,
        },
        .{
            .id = 'z',
            .names = .{ .long = "preserve-fds" },
            .takes_value = .one,
        },
    };

    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = iter,
        .diagnostic = &diag,
    };

    var container_builder = libcontainer.ContainerBuilder{};
    container_builder.rootDir = try libcontainer.initRootPath(main_args.args.root);

    if (systemd_cgroup) {
        container_builder.systemdCgroup = true;
    }

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (parser.next() catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    }) |arg| {
        switch (arg.param.id) {
            'h' => return usage(),
            'n' => if (arg.value) |value| {
                container_builder.containerID = value;
            },
            'b' => if (arg.value) |value| {
                container_builder.bundleDir = value;
            },
            'f' => if (arg.value) |value| {
                container_builder.spec = value;
            },
            'u' => container_builder.noPivot = true,
            'w' => container_builder.noNewKeyring = true,
            'x' => if (arg.value) |value| {
                container_builder.consoleSocket = value;
            },
            'y' => if (arg.value) |value| {
                container_builder.pidFile = value;
            },
            'z' => if (arg.value) |value| {
                container_builder.preservedFDs = try std.fmt.parseInt(u32, value, 10);
            },

            else => return libcontainer.Error.InvalidContainerCreateOptions,
        }
    }

    try container_builder.initBuilder();
}

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: create [OPTION...]\n\n", .{});
    try stdout.print("  -b, --bundle=DIR             {s}\n", .{"path to the root of the bundle dir (default \".\")"});
    try stdout.print("  -f, --config=PATH            {s}\n", .{"destination file"});
    try stdout.print("  -n, --name=NAME              {s}\n", .{"container name"});
    try stdout.print("      --no-pivot               {s}\n", .{"do not use pivot_root"});
    try stdout.print("      --no-new-keyring         {s}\n", .{"keep the same session key"});
    try stdout.print("      --console-socket=SOCK    {s}\n", .{"path to a socket that will receive the ptmx end of the tty"});
    try stdout.print("      --pid-file=PATH          {s}\n", .{"where to write the PID of the container"});
    try stdout.print("      --preserve-fds=N         {s}\n", .{"pass additional FDs to the container"});
    try stdout.print("  -h, --help                   {s}\n\n", .{"display help and exit"});
}
