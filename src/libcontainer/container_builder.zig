const std = @import("std");
const errors = @import("errors.zig");
const container = @import("container.zig");
const state = @import("state.zig");
const ocispec = @import("ocispec");
const runtime = ocispec.runtime;
const config = @import("config.zig");
const userns = @import("userns.zig");

pub const ContainerBuilder = struct {
    bundleDir: []const u8 = "",
    rootDir: []const u8 = "",
    spec: []const u8 = "",
    containerID: []const u8 = "",
    systemdCgroup: bool = false,
    rootless: ?bool = null,
    noPivot: ?bool = null,
    noNewKeyring: ?bool = null,
    consoleSocket: ?[]const u8 = null,
    pidFile: ?[]const u8 = null,
    preservedFDs: ?u32 = null,

    pub fn init(name: []const u8, bundle: []const u8, root: []const u8, spec: []const u8) ContainerBuilder {
        return ContainerBuilder{
            .containerID = name,
            .bundleDir = bundle,
            .rootDir = root,
            .spec = spec,
        };
    }

    pub fn initBuilder(self: @This()) !void {
        try self.validate();

        std.log.debug("root directory: {s}", .{self.rootDir});
        std.log.debug("bundle directory: {s}", .{self.bundleDir});
        std.log.debug("runtime config: {s}", .{self.spec});
        std.log.debug("container name: {s}", .{self.containerID});
        std.log.debug("no pivot: {any}", .{self.noPivot});
        std.log.debug("no new keyring: {any}", .{self.noNewKeyring});
        std.log.debug("console socket: {any}", .{self.consoleSocket});
        std.log.debug("pid file: {any}", .{self.pidFile});
        std.log.debug("systemd cgroup {any}:", .{self.systemdCgroup});
        std.log.debug("preserve fds {any}:", .{self.preservedFDs});

        const spec = try runtime.Spec.initFromFile(self.spec);

        const container_dir = try self.createContainerDir();
        const cnt = container.Container.init(self.containerID, state.ContainerStatus.Creating, null, self.bundleDir, container_dir);

        const userns_config = try userns.UserNamespaceConfig.init(&spec);
        std.debug.print("userns_config: {any}\n", .{userns_config});

        const cnt_config = try config.Config.init_from_spec(&spec, self.containerID);
        try cnt_config.save(container_dir);

        try cnt.save();
    }

    pub fn createContainerDir(self: @This()) ![]const u8 {
        var container_dir = try std.mem.concat(std.heap.page_allocator, u8, &.{ self.rootDir, self.containerID });
        container_dir = try std.mem.concat(std.heap.page_allocator, u8, &.{ container_dir, "/" });

        try std.fs.makeDirAbsolute(container_dir);

        return container_dir;
    }

    fn validate(self: @This()) !void {
        if (self.bundleDir.len == 0) {
            return errors.Error.InvalidBundleDir;
        }

        if (self.spec.len == 0) {
            return errors.Error.InvalidConfigfile;
        }

        if (self.rootDir.len == 0) {
            return errors.Error.InvalidRootDir;
        }

        if (self.containerID.len == 0) {
            return errors.Error.InvalidContainerID;
        }
    }
};
