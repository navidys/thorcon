const std = @import("std");

pub const CreateOptions = struct {
    rootless: ?bool = null,
    bundleDir: []const u8,
    file: []const u8,
    noPivot: ?bool = null,
    noNewKeyring: ?bool = null,
    containerID: []const u8,
    consoleSocket: ?[]const u8 = null,
    pidFile: ?[]const u8 = null,
};

pub fn create(opts: *const CreateOptions) !void {
    std.log.debug("bundle directory: {s}", .{opts.bundleDir});
    std.log.debug("runtime config: {s}", .{opts.file});
    std.log.debug("container name: {s}", .{opts.containerID});
    std.log.debug("no pivot: {any}", .{opts.noPivot});
    std.log.debug("no new keyring: {any}", .{opts.noNewKeyring});
    std.log.debug("console socket: {any}", .{opts.consoleSocket});
    std.log.debug("pid file: {any}", .{opts.pidFile});
}
