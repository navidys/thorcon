const std = @import("std");

pub const CreateOptions = struct {
    rootless: ?bool = null,
    bundleDir: []const u8,
    file: []const u8,
    noPivot: ?bool = null,
    consoleSocket: ?[]const u8 = null,
    pidFile: ?[]const u8 = null,
};

pub fn create(opts: *const CreateOptions) !void {
    std.log.debug("bundle directory: {s}", .{opts.bundleDir});
    std.log.debug("runtime config: {s}", .{opts.file});
    std.log.debug("no pivot: {any}", .{opts.noPivot});
    std.log.debug("console socket: {any}", .{opts.consoleSocket});
    std.log.debug("pid file: {any}", .{opts.pidFile});
}
