const std = @import("std");
const ocispec = @import("ocispec");
const errors = @import("errors.zig");
const runtime = ocispec.runtime;

const CONFIG_NAME: []const u8 = "thorcon_config.json";

pub const Config = struct {
    hooks: ?runtime.Hooks = null,
    cgroup_path: []const u8,

    pub fn init_from_spec(spec: *const runtime.Spec, id: []const u8) !Config {
        var path: ?[]const u8 = null;
        if (spec.linux) |linux| {
            if (linux.cgroupsPath) |cpath| {
                path = cpath;
            }
        }

        const cpath = try get_cgroup_path(path, id);

        return Config{
            .hooks = spec.hooks,
            .cgroup_path = cpath,
        };
    }

    pub fn save(self: @This(), path: []const u8) !void {
        const gpa = std.heap.page_allocator;

        const content = std.json.stringifyAlloc(
            gpa,
            self,
            .{ .emit_strings_as_arrays = false, .emit_null_optional_fields = false },
        ) catch |err| {
            std.debug.print("config content stringifyAlloc: {any}\n", .{err});

            return errors.Error.ConfigFileParseError;
        };

        const config_file = std.mem.concat(gpa, u8, &.{ path, CONFIG_NAME }) catch |err| {
            std.debug.print("config file path concat: {any}\n", .{err});

            return errors.Error.ConfigFileWriteError;
        };

        const file = std.fs.cwd().createFile(config_file, std.fs.File.CreateFlags{ .read = false }) catch |err| {
            std.debug.print("config file create: {any}\n", .{err});

            return errors.Error.ConfigFileCreateError;
        };

        defer file.close();

        file.writeAll(content) catch |err| {
            std.debug.print("config file write: {any}\n", .{err});

            return errors.Error.ConfigFileWriteError;
        };

        std.debug.print("config saved: {s}\n", .{config_file});
    }

    pub fn load(path: []const u8) !Config {
        const gpa = std.heap.page_allocator;

        const config_file = std.mem.concat(gpa, u8, &.{ path, CONFIG_NAME }) catch |err| {
            std.debug.print("config file path concat: {any}\n", .{err});

            return errors.Error.ConfigFileReadError;
        };

        const file = std.fs.cwd().openFile(config_file, std.fs.File.OpenFlags{ .mode = .read_only }) catch |err| {
            std.debug.print("config file open: {any}\n", .{err});

            return errors.Error.ConfigFileOpenError;
        };
        defer file.close();

        const file_size = try file.getEndPos();

        const buffer = try gpa.alloc(u8, file_size);

        file.readAll(buffer) catch |err| {
            std.debug.print("config file read: {any}\n", err);

            return errors.Error.ConfigFileReadError;
        };

        defer gpa.free(buffer);

        const parsed = try std.json.parseFromSlice(
            Config,
            gpa,
            buffer,
            .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
        );

        std.debug.print("config loaded: {s}\n", .{config_file});

        return parsed.value;
    }

    fn get_cgroup_path(path: ?[]const u8, id: []const u8) ![]const u8 {
        if (path) |p| {
            return p;
        }

        const cpath = try std.mem.concat(std.heap.page_allocator, u8, &.{ ":thorcon:", id });

        return cpath;
    }
};
