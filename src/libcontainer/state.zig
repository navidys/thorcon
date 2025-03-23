const std = @import("std");
const utils = @import("utils.zig");
const datetime = @import("datetime");
const fs = std.fs;

const STATE_FILE = "state.json";
const LOCK_FILE = "state.lock";
const PID_FILE = "pid";

pub const ContainerState = struct {
    stateFile: []const u8,
    lockFile: []const u8,
    bundleDir: []const u8,
    rootfsDir: []const u8,
    specFile: []const u8,
    pidFile: []const u8,
    noPivot: bool,
    created: []const u8,
    status: ContainerStatus,

    pub fn init(rootDir: []const u8, bundleDir: []const u8, rootfs: []const u8, spec: []const u8, noPivot: bool) !ContainerState {
        const gpa = std.heap.page_allocator;
        const stateFile = try getStateFileName(rootDir);
        const pidfile = try getPidFileName(rootDir);
        const lockfile = try getLockFileName(rootDir);

        std.log.debug("state file: {s}", .{stateFile});
        std.log.debug("lock file: {s}", .{lockfile});

        const currenTime = datetime.datetime.Datetime.now();
        const created = try currenTime.formatHttp(gpa);

        try utils.writeFileContent(lockfile, "");

        return ContainerState{
            .noPivot = noPivot,
            .bundleDir = bundleDir,
            .specFile = spec,
            .rootfsDir = rootfs,
            .pidFile = pidfile,
            .status = ContainerStatus.Init,
            .stateFile = stateFile,
            .lockFile = lockfile,
            .created = created,
        };
    }

    pub fn initFromFile(rootDir: []const u8) !ContainerState {
        const gpa = std.heap.page_allocator;
        const lockfilePath = try getLockFileName(rootDir);
        const stateFilePath = try getStateFileName(rootDir);
        const lockfile = try fs.cwd().openFile(lockfilePath, fs.File.OpenFlags{ .mode = .read_only });
        defer lockfile.close();

        try fs.File.lock(lockfile, .exclusive);

        const content = try utils.readFileContent(stateFilePath, gpa);
        defer gpa.free(content);

        const stateParsed = try std.json.parseFromSlice(
            ContainerState,
            gpa,
            content,
            .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
        );

        fs.File.unlock(lockfile);

        return stateParsed.value;
    }

    pub fn writeStateFile(self: @This()) !void {
        const lockfile = try fs.cwd().openFile(self.lockFile, fs.File.OpenFlags{ .mode = .read_only });
        defer lockfile.close();

        try fs.File.lock(lockfile, .exclusive);

        const content = try utils.toJsonString(self, true);
        const content_newline = try std.mem.concat(
            std.heap.page_allocator,
            u8,
            &.{ content, "\n" },
        );

        try utils.writeFileContent(self.stateFile, content_newline);

        fs.File.unlock(lockfile);
    }

    fn getLockFileName(rootDir: []const u8) ![]const u8 {
        return std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ rootDir, LOCK_FILE });
    }

    fn getStateFileName(rootDir: []const u8) ![]const u8 {
        return std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ rootDir, STATE_FILE });
    }

    fn getPidFileName(rootDir: []const u8) ![]const u8 {
        return std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ rootDir, PID_FILE });
    }
};

pub const ContainerStatus = enum {
    Init,
    Creating,
    Created,
    Running,
    Stopped,
    Paused,

    pub fn toString(self: @This()) []const u8 {
        switch (self) {
            .Init => return "init",
            .Creating => return "creating",
            .Created => return "created",
            .Running => return "running",
            .Stopped => return "stopped",
            .Paused => return "paused",
        }
    }
};
