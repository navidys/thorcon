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
            .id = 'f',
            .names = .{ .short = 'f', .long = "format" },
            .takes_value = .one,
        },
        .{
            .id = 'q',
            .names = .{ .short = 'q', .long = "quiet" },
        },
    };

    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = iter,
        .diagnostic = &diag,
    };

    var format: []const u8 = "table";
    var quietDisplay = false;

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (parser.next() catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    }) |arg| {
        switch (arg.param.id) {
            'h' => return usage(),
            'f' => if (arg.value) |value| {
                if (std.mem.eql(u8, value, "table")) {
                    format = value;

                    continue;
                }

                if (std.mem.eql(u8, value, "json")) {
                    format = value;

                    continue;
                }

                return libcontainer.errors.Error.InvalidContainerListOptions;
            },
            'q' => quietDisplay = true,
            else => return libcontainer.errors.Error.InvalidContainerListOptions,
        }
    }

    const containers = try libcontainer.list.ListContainers(main_args.args.root);

    if (quietDisplay) {
        try displayIDs(containers);

        return;
    }

    if (std.mem.eql(u8, format, "json")) {
        try displayJson(containers);

        return;
    }

    // display table content
    try displayTable(containers);

    return;
}

fn displayJson(containers: []libcontainer.list.ContainerReport) !void {
    const stdout = std.io.getStdOut().writer();

    const jsonOutput = try libcontainer.utils.toJsonString(containers, true);

    try stdout.print("{s}", .{jsonOutput});

    return;
}

fn displayIDs(containers: []libcontainer.list.ContainerReport) !void {
    const stdout = std.io.getStdOut().writer();
    var containerIDs: []const u8 = "";

    for (containers) |container| {
        containerIDs = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "{s}{s}\n",
            .{ containerIDs, container.name },
        );
    }

    try stdout.print("{s}", .{containerIDs});

    return;
}

fn displayTable(containers: []libcontainer.list.ContainerReport) !void {
    const stdout = std.io.getStdOut().writer();

    var tableContent: []const u8 = "";
    var maxNameColWidth: usize = 5;
    var maxPidColWidth: usize = 5;
    var maxStatusColWidth: usize = 8;
    var maxBundleColWidth: usize = 12;
    var maxCreatedColWidth: usize = 30;

    for (containers) |container| {
        if (container.name.len > maxNameColWidth) {
            maxNameColWidth = container.name.len;
        }

        if (container.pid.len > maxPidColWidth) {
            maxPidColWidth = container.pid.len;
        }

        const statusLen = container.status.toString().len;
        if (statusLen > maxStatusColWidth) {
            maxStatusColWidth = statusLen;
        }

        if (container.bundle.len > maxBundleColWidth) {
            maxBundleColWidth = container.bundle.len;
        }

        if (container.created.len > maxCreatedColWidth) {
            maxCreatedColWidth = container.created.len;
        }
    }

    var nameHeaderCol: []const u8 = "NAME";
    var pidHeaderCol: []const u8 = "PID";
    var statusHeaderCol: []const u8 = "STATUS";
    var bundlePathHeaderCol: []const u8 = "BUNDLE PATH";
    var createdHeaderCol: []const u8 = "CREATED";

    nameHeaderCol = try fillSpace(nameHeaderCol, maxNameColWidth);
    pidHeaderCol = try fillSpace(pidHeaderCol, maxPidColWidth);
    statusHeaderCol = try fillSpace(statusHeaderCol, maxStatusColWidth);
    bundlePathHeaderCol = try fillSpace(bundlePathHeaderCol, maxBundleColWidth);
    createdHeaderCol = try fillSpace(createdHeaderCol, maxCreatedColWidth);

    tableContent = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "{s}  {s}  {s}  {s}  {s}\n",
        .{ nameHeaderCol, pidHeaderCol, statusHeaderCol, bundlePathHeaderCol, createdHeaderCol },
    );

    for (containers) |container| {
        const cntNameCol = try fillSpace(container.name, maxNameColWidth);
        const cntPidCol = try fillSpace(container.pid, maxPidColWidth);
        const cntStatusCol = try fillSpace(container.status.toString(), maxStatusColWidth);
        const cntBundlePathCol = try fillSpace(container.bundle, maxBundleColWidth);
        const cntCreatedCol = try fillSpace(container.created, maxCreatedColWidth);

        tableContent = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "{s}{s}  {s}  {s}  {s}  {s}\n",
            .{ tableContent, cntNameCol, cntPidCol, cntStatusCol, cntBundlePathCol, cntCreatedCol },
        );
    }

    try stdout.print("{s}", .{tableContent});

    return;
}

fn fillSpace(content: []const u8, maxIndex: usize) ![]const u8 {
    const diffIndex = maxIndex - content.len;
    if (diffIndex < 0) {
        diffIndex = 0;
    }

    var newContent = content;
    var index: usize = 0;
    while (index < diffIndex) {
        newContent = try std.fmt.allocPrint(std.heap.page_allocator, "{s} ", .{newContent});

        index += 1;
    }

    return newContent;
}

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: list [OPTION...] \n\n", .{});
    try stdout.print("  -f, --format                 {s}\n", .{"select one of: table or json (default: \"table\")"});
    try stdout.print("  -q, --quiet                  {s}\n", .{"show only IDs"});
    try stdout.print("  -h, --help                   {s}\n\n", .{"display help and exit"});
}
