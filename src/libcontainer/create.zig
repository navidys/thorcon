const std = @import("std");
const errors = @import("errors.zig");
const ocispec = @import("ocispec");
const utils = @import("utils.zig");
const cntruntime = @import("runtime.zig");
const filesystem = @import("filesystem.zig");
const cntstate = @import("state.zig");
const cntlist = @import("list.zig");
const runtime = ocispec.runtime;

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

    std.log.debug("container name: {s}", .{opts.name});

    if (try cntlist.ContainerExist(rootDir, opts.name)) {
        return errors.Error.ContainerExist;
    }

    const rootdir = try filesystem.initRootPath(rootDir, opts.name);

    std.log.debug("root directory: {s}", .{rootdir});

    if (opts.bundleDir.len != 0) {
        bundledir = try utils.canonicalPath(opts.bundleDir);
    }

    std.log.debug("bundle directory: {s}", .{bundledir});

    if (opts.spec.len != 0) {
        cntspec = opts.spec;
    } else {
        cntspec = try std.mem.concat(std.heap.page_allocator, u8, &.{ bundledir, "/", cntspec });
    }

    std.log.debug("runtime config: {s}", .{cntspec});

    const containe_spec = try runtime.Spec.initFromFile(cntspec);

    var rootfs = containe_spec.root.path;
    if (rootfs.len == 0)
        return errors.Error.SpecRootFsError;

    if (rootfs[rootfs.len - 1] != '/') {
        rootfs = try std.mem.concat(std.heap.page_allocator, u8, &.{ rootfs, "/" });
        rootfs = try std.mem.concat(std.heap.page_allocator, u8, &.{ "/", rootfs });
        rootfs = try std.mem.concat(std.heap.page_allocator, u8, &.{ bundledir, rootfs });
        rootfs = try utils.canonicalPath(rootfs);
    }

    std.log.debug("rootfs: {s}", .{rootfs});

    // init and write state file
    var containerState = try cntstate.ContainerState.init(
        rootdir,
        bundledir,
        rootfs,
        cntspec,
        opts.noPivot,
    );
    try containerState.writeStateFile();

    // change container state status to created and write
    containerState.status = cntstate.ContainerStatus.Created;
    try containerState.writeStateFile();
}
