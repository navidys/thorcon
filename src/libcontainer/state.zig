const std = @import("std");
const ocispec = @import("ocispec");
const runtime = ocispec.runtime;
const errors = @import("errors.zig");

const STATE_FILE_NAME: []const u8 = "state.json";

pub const ContainerStatus = enum {
    Creating,
    Created,
    Running,
    Stopped,
    Paused,

    pub fn canStart(self: ContainerStatus) bool {
        return self == ContainerStatus.Created;
    }

    pub fn canKill(self: ContainerStatus) bool {
        switch (self) {
            ContainerStatus.Creating => return false,
            ContainerStatus.Stopped => return false,
            ContainerStatus.Created => return true,
            ContainerStatus.Running => return true,
            ContainerStatus.Paused => return true,
            else => return false,
        }
    }

    pub fn canDelete(self: ContainerStatus) bool {
        return self == ContainerStatus.Stopped;
    }

    pub fn canPause(self: ContainerStatus) bool {
        return self == ContainerStatus.Running;
    }

    pub fn canResume(self: ContainerStatus) bool {
        return self == ContainerStatus.Paused;
    }

    pub fn canExec(self: ContainerStatus) bool {
        return self == ContainerStatus.Running;
    }
};

pub const ContainerState = struct {
    ociVersion: []const u8,
    id: []const u8,
    status: ContainerStatus,
    pid: ?i32 = null,
    bundle: []const u8,
    annotations: ?std.json.ArrayHashMap([]const u8) = null,
    created: ?[]const u8 = null,
    creator: ?[]const u8 = null,
    useSystemd: bool = false,
    cleanupIntelRdtSubDir: ?bool = null,

    pub fn init(id: []const u8, status: ContainerStatus, pid: ?i32, bundle: []const u8) ContainerState {
        return ContainerState{
            .ociVersion = runtime.VERSION,
            .id = id,
            .status = status,
            .pid = pid,
            .bundle = bundle,
        };
    }

    pub fn load(root: []const u8) !ContainerState {
        const gpa = std.heap.page_allocator;

        const state_file = std.mem.concat(gpa, u8, &.{ root, STATE_FILE_NAME }) catch |err| {
            std.debug.print("state file path concat: {any}\n", .{err});

            return errors.Error.StateFileReadError;
        };

        const file = std.fs.cwd().openFile(state_file, std.fs.File.OpenFlags{ .mode = .read_only }) catch |err| {
            std.debug.print("state file open: {any}\n", .{err});

            return errors.Error.StateFileOpenError;
        };
        defer file.close();

        const file_size = try file.getEndPos();

        const buffer = try gpa.alloc(u8, file_size);

        file.readAll(buffer) catch |err| {
            std.debug.print("state file read: {any}\n", err);

            return errors.Error.StateFileReadError;
        };

        defer gpa.free(buffer);

        const parsed = try std.json.parseFromSlice(
            ContainerState,
            gpa,
            buffer,
            .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
        );

        std.debug.print("container state loaded: {s}\n", .{state_file});

        return parsed.value;
    }

    pub fn save(self: @This(), root: []const u8) !void {
        const gpa = std.heap.page_allocator;

        const content = std.json.stringifyAlloc(
            gpa,
            self,
            .{ .emit_strings_as_arrays = false, .emit_null_optional_fields = false },
        ) catch |err| {
            std.debug.print("state content stringifyAlloc: {any}\n", .{err});

            return errors.Error.StateFileParseError;
        };

        const state_file = std.mem.concat(gpa, u8, &.{ root, STATE_FILE_NAME }) catch |err| {
            std.debug.print("state file path concat: {any}\n", .{err});

            return errors.Error.StateFileWriteError;
        };

        const file = std.fs.cwd().createFile(state_file, std.fs.File.CreateFlags{ .read = false }) catch |err| {
            std.debug.print("state file create: {any}\n", .{err});

            return errors.Error.StateFileCreateError;
        };

        defer file.close();

        file.writeAll(content) catch |err| {
            std.debug.print("state file write: {any}\n", .{err});

            return errors.Error.StateFileWriteError;
        };

        std.debug.print("container state saved: {s}\n", .{state_file});
    }
};
