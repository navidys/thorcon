const std = @import("std");
const errors = @import("errors.zig");
const utils = @import("utils.zig");
const filesystem = @import("filesystem.zig");
const runtime = @import("runtime.zig");
const cleanup = @import("cleanup.zig");
const cntstate = @import("state.zig");

pub const CreateOptions = struct {
    name: []const u8,
    bundleDir: []const u8,
    spec: []const u8,
    noPivot: bool = false,
};

pub fn createContainer(rootDir: ?[]const u8, opts: *const CreateOptions) !void {
    var bundledir: []const u8 = ".";
    var cntspec: []const u8 = "config.json";

    if (opts.name.len == 0) {
        return errors.Error.InvalidContainerName;
    }

    if (opts.bundleDir.len != 0) {
        bundledir = try utils.canonicalPath(opts.bundleDir);
    }

    if (opts.spec.len != 0) {
        cntspec = opts.spec;
    } else {
        cntspec = try std.mem.concat(std.heap.page_allocator, u8, &.{ bundledir, "/", cntspec });
    }

    const rootdir = try filesystem.initRootPath(rootDir, null);
    const cntRootDir = try filesystem.initRootPath(rootdir, opts.name);

    const cntStateResult = cntstate.ContainerState.getContainerState(cntRootDir);
    var canCreate = false;

    if (cntStateResult) |result| {
        if (!result.status.canCreate()) {
            return errors.Error.ContainerInvalidStatus;
        }

        canCreate = true;
    } else |err| {
        if (err != std.fs.File.OpenError.FileNotFound) {
            return err;
        }

        canCreate = true;
    }

    if (!canCreate) {
        return;
    }

    try cleanup.refreshAllContainersState(rootdir);
    try runtime.createContainer(opts.name, cntRootDir, bundledir, cntspec, opts.noPivot);
}

fn create() !void {}
