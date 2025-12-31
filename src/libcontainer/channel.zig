const std = @import("std");

pub const PChannelAction = enum {
    Undefined,
    PreInitOK,
    Init,
    InitOK,
    Exec,

    pub fn toString(self: PChannelAction) []const u8 {
        return switch (self) {
            .PreInitOK => "pre_init_ok",
            .Init => "init",
            .InitOK => "init_ok",
            .Exec => "exec",
            else => "undefined",
        };
    }

    pub fn fromString(val: []const u8) PChannelAction {
        if (std.mem.eql(u8, val, "pre_init_ok")) {
            return PChannelAction.PreInitOK;
        }

        if (std.mem.eql(u8, val, "init")) {
            return PChannelAction.Init;
        }

        if (std.mem.eql(u8, val, "init_ok")) {
            return PChannelAction.InitOK;
        }

        if (std.mem.eql(u8, val, "exec")) {
            return PChannelAction.Exec;
        }

        return PChannelAction.Undefined;
    }
};

pub const PChannel = struct {
    reader: i32,
    writer: i32,
    fdReader: i32,
    fdWriter: i32,
    fdPID: usize,

    const Self = @This();

    pub fn init() !Self {
        const fds = try std.posix.pipe();
        const reader = fds[0];
        const writer = fds[1];

        return Self{ .reader = reader, .writer = writer, .fdReader = -1, .fdWriter = -1, .fdPID = 0 };
    }

    pub fn initFromFDs(pid: usize, reader: i32, writer: i32) !Self {
        return Self{ .reader = -1, .writer = -1, .fdReader = reader, .fdWriter = writer, .fdPID = pid };
    }

    pub fn sendWithFD(self: *Self, value: PChannelAction) !void {
        std.debug.print("debug: channel action sendFD {any}\n", .{value});
        const gpa = std.heap.page_allocator;
        const writerPath = try std.fmt.allocPrint(gpa, "/proc/{d}/fd/{d}", .{ self.fdPID, self.fdWriter });
        const cwd = std.fs.cwd();
        const openFlag = std.fs.File.OpenFlags{ .mode = .read_write };
        const file = try cwd.openFile(writerPath, openFlag);
        defer file.close();

        _ = try std.posix.write(file.handle, value.toString());
    }

    pub fn send(self: *Self, value: PChannelAction) !void {
        std.debug.print("debug: channel action send {any}\n", .{value});

        _ = try std.posix.write(self.writer, value.toString());
    }

    pub fn receive(self: *Self) !PChannelAction {
        std.debug.print("debug: channel action receive loop started\n", .{});
        while (true) {
            var buffer: [1024]u8 = undefined;
            const rsize = try std.posix.read(self.reader, &buffer);

            const actVal = PChannelAction.fromString(buffer[0..rsize]);
            if (actVal != PChannelAction.Undefined) {
                return actVal;
            }
        }
    }
};
