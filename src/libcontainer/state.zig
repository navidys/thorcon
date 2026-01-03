const std = @import("std");
const utils = @import("utils.zig");
const datetime = @import("datetime");
const fs = std.fs;

const STATE_FILE = "state.json";
const LOCK_FILE = "state.lock";
const PID_FILE = "pid";

pub const ContainerState = struct {
    runDir: []const u8,
    stateFile: []const u8,
    lockFile: []const u8,
    bundleDir: []const u8,
    rootfsDir: []const u8,
    specFile: []const u8,
    pidFile: []const u8,
    noPivot: bool,
    created: []const u8,
    status: ContainerStatus,
    commReader: i32,
    commWriter: i32,

    pub fn init(pid: i32, rootDir: []const u8, bundleDir: []const u8, rootfs: []const u8, spec: []const u8, noPivot: bool, reader: i32, writer: i32) !ContainerState {
        const gpa = std.heap.page_allocator;
        const stateFile = try getStateFileName(rootDir);
        const pidfile = try getPidFileName(rootDir);
        const lockfile = try getLockFileName(rootDir);

        std.log.debug("pid {} state file: {s}", .{ pid, stateFile });
        std.log.debug("pid {} spid file: {s}", .{ pid, pidfile });
        std.log.debug("pid {} slock file: {s}", .{ pid, lockfile });

        const currenTime = datetime.datetime.Datetime.now();
        const created = try currenTime.formatHttp(gpa);

        try utils.writeFileContent(lockfile, "");

        return ContainerState{
            .noPivot = noPivot,
            .runDir = rootDir,
            .bundleDir = bundleDir,
            .specFile = spec,
            .rootfsDir = rootfs,
            .pidFile = pidfile,
            .status = ContainerStatus.Undefined,
            .stateFile = stateFile,
            .lockFile = lockfile,
            .created = created,
            .commReader = reader,
            .commWriter = writer,
        };
    }

    pub fn getContainerState(rootDir: []const u8) !ContainerState {
        const lfile = try getLockFileName(rootDir);
        const lockfile = try fs.cwd().openFile(lfile, fs.File.OpenFlags{ .mode = .read_only });
        defer lockfile.close();

        try fs.File.lock(lockfile, .exclusive);

        defer fs.File.unlock(lockfile);

        const gpa = std.heap.page_allocator;
        const stateFilePath = try getStateFileName(rootDir);

        const content = try utils.readFileContent(stateFilePath, gpa);
        defer gpa.free(content);

        const stateParsed = try std.json.parseFromSlice(
            ContainerState,
            gpa,
            content,
            .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
        );

        return stateParsed.value;
    }

    pub fn writeStateFile(self: @This()) !void {
        try self.lock();
        defer self.unlock() catch |err| {
            std.log.err("container state unlock: {any}", .{err});
        };

        const content = try utils.toJsonString(self, true);
        const content_newline = try std.mem.concat(
            std.heap.page_allocator,
            u8,
            &.{ content, "\n" },
        );

        try utils.writeFileContent(self.stateFile, content_newline);
    }

    pub fn writePID(self: @This(), pid: usize) !void {
        try self.lock();
        defer self.unlock() catch |err| {
            std.log.err("container state unlock: {any}", .{err});
        };

        const cwd = std.fs.cwd();
        const createFlag = std.fs.File.CreateFlags{ .read = false };
        const file = try cwd.createFile(self.pidFile, createFlag);

        defer file.close();

        const content = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{pid});

        _ = try file.write(content);
    }

    pub fn readPID(self: @This()) !usize {
        try self.lock();
        defer self.unlock() catch |err| {
            std.log.err("container state unlock: {any}", .{err});
        };

        const cwd = std.fs.cwd();
        const openFlag = std.fs.File.OpenFlags{ .mode = .read_only };
        const file = try cwd.openFile(self.pidFile, openFlag);

        defer file.close();

        const buffer = try file.readToEndAlloc(std.heap.page_allocator, 1024);
        defer std.heap.page_allocator.free(buffer);

        const trimmed = std.mem.trim(u8, buffer, "\n\r ");
        const pidVal = try std.fmt.parseInt(usize, trimmed, 10);

        return pidVal;
    }

    pub fn setStatus(self: *@This(), status: ContainerStatus) !void {
        try self.lock();
        defer self.unlock() catch |err| {
            std.log.err("container state unlock: {any}", .{err});
        };

        self.status = status;
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

    fn lock(self: @This()) !void {
        const lockfile = try fs.cwd().openFile(self.lockFile, fs.File.OpenFlags{ .mode = .read_only });
        defer lockfile.close();

        try fs.File.lock(lockfile, .exclusive);
    }

    fn unlock(self: @This()) !void {
        const lockfile = try fs.cwd().openFile(self.lockFile, fs.File.OpenFlags{ .mode = .read_only });
        defer lockfile.close();

        fs.File.unlock(lockfile);
    }
};

pub const ContainerStatus = enum {
    Undefined,
    Creating,
    Created,
    Running,
    Stopped,
    Paused,

    pub fn toString(self: @This()) []const u8 {
        return switch (self) {
            .Creating => return "creating",
            .Created => return "created",
            .Running => return "running",
            .Stopped => return "stopped",
            .Paused => return "paused",
            else => "undefined",
        };
    }

    pub fn canStart(self: @This()) bool {
        return (self == .Created);
    }

    pub fn canKill(self: @This()) bool {
        return switch (self) {
            .Creating => return false,
            .Created => return true,
            .Running => return true,
            .Stopped => return false,
            .Paused => return true,
            else => false,
        };
    }

    pub fn canCreate(self: @This()) bool {
        return switch (self) {
            .Creating => return false,
            .Created => return false,
            .Running => return false,
            .Stopped => return true,
            .Paused => return true,
            .Undefined => return true,
        };
    }

    pub fn canDelete(self: @This()) bool {
        return (self == .Stopped or self == .Undefined);
    }

    pub fn canPause(self: @This()) bool {
        return (self == .Running);
    }

    pub fn canResume(self: @This()) bool {
        return (self == .Paused);
    }
};
