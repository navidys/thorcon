const std = @import("std");
const errors = @import("errors.zig");
const ocispec = @import("ocispec");
const rootpath = @import("rootpath.zig");
const utils = @import("utils.zig");
const cntrun = @import("run.zig");
const runtime = ocispec.runtime;

pub const ContainerManager = struct {
    name: []const u8,
    bundleDir: []const u8,
    rootDir: []const u8,
    rootfs: []const u8 = "",
    spec: []const u8,
    rootless: ?bool = null,

    pub fn init(name: []const u8, bundle: []const u8, root: ?[]const u8, spec: []const u8) !ContainerManager {
        var bundledir: []const u8 = ".";
        var cntspec: []const u8 = "config.json";

        if (name.len == 0) {
            return errors.Error.InvalidContainerName;
        }

        if (bundle.len != 0) {
            bundledir = try utils.canonicalPath(bundle);
        }

        if (spec.len != 0) {
            cntspec = spec;
        } else {
            cntspec = try std.mem.concat(std.heap.page_allocator, u8, &.{ bundledir, "/", cntspec });
        }

        const rootdir = try rootpath.initRootPath(root);
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

        std.log.debug("name: {s}", .{name});
        std.log.debug("root directory: {s}", .{rootdir});
        std.log.debug("bundle directory: {s}", .{bundledir});
        std.log.debug("rootfs: {s}", .{rootfs});
        std.log.debug("runtime config: {s}", .{cntspec});

        return ContainerManager{
            .name = name,
            .rootfs = rootfs,
            .bundleDir = bundledir,
            .rootDir = rootdir,
            .spec = cntspec,
        };
    }

    pub fn run(self: @This()) !void {
        try cntrun.container_run(self.rootfs, self.spec);
    }
};
