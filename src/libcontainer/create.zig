const std = @import("std");
const ocispec = @import("ocispec");
const errors = @import("errors.zig");
const utils = @import("utils.zig");
const filesystem = @import("filesystem.zig");
const runtime = @import("runtime.zig");
const cleanup = @import("cleanup.zig");
const channel = @import("channel.zig");
const cntstate = @import("state.zig");
const namespace = @import("namespace.zig");

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

    try cleanup.refreshAllContainersState(rootdir);

    const cntStateResult = cntstate.ContainerState.initFromRootDir(cntRootDir);
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

    try create(opts.name, cntRootDir, bundledir, cntspec, opts.noPivot);
}

fn create(name: []const u8, rootdir: []const u8, bundle: []const u8, spec: []const u8, noPivot: bool) !void {
    const runspec = try ocispec.runtime.Spec.initFromFile(spec);
    const rootfs = try utils.getRootFSPath(bundle, runspec.root.path);

    const pid = std.os.linux.getpid();

    var pcomm = try channel.PChannel.init();
    var ccomm = try channel.PChannel.init();

    std.log.debug("pid {} container name {s}", .{ pid, name });
    std.log.debug("pid {} root directory: {s}", .{ pid, rootdir });
    std.log.debug("pid {} bundle directory: {s}", .{ pid, bundle });
    std.log.debug("pid {} runtime config: {s}", .{ pid, spec });
    std.log.debug("pid {} rootfs: {s}", .{ pid, rootfs });
    std.log.debug("pid {} noPivot: {any}", .{ pid, noPivot });

    var options = runtime.RuntimeOptions{
        .name = name,
        .bundle = bundle,
        .rootdir = rootdir,
        .rootfs = rootfs,
        .spec = spec,
        .noPivot = noPivot,
        .runtimeSpec = runspec,
        .pcomm = &pcomm,
        .ccomm = &ccomm,
    };

    try runtime.create(pid, &options);
}
