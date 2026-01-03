const std = @import("std");

pub const PChannelAction = enum {
    Undefined,
    UserMapRequest,
    UserMapOK,
    Ready,
    Start,

    pub fn toString(self: PChannelAction) []const u8 {
        return switch (self) {
            .UserMapRequest => "user_map_request",
            .UserMapOK => "user_map_ok",
            .Ready => "ready",
            .Start => "start",
            else => "undefined",
        };
    }

    pub fn fromString(val: []const u8) PChannelAction {
        if (std.mem.eql(u8, val, "user_map_request")) {
            return PChannelAction.UserMapRequest;
        }

        if (std.mem.eql(u8, val, "user_map_ok")) {
            return PChannelAction.UserMapOK;
        }

        if (std.mem.eql(u8, val, "start")) {
            return PChannelAction.Start;
        }

        if (std.mem.eql(u8, val, "ready")) {
            return PChannelAction.Ready;
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

    pub fn send(self: *Self, value: PChannelAction, data: anytype) !void {
        std.debug.print("debug: channel action send {any} data {any}\n", .{ value, data });

        const sendData = try std.fmt.allocPrint(std.heap.page_allocator, "{s}:{any}", .{ value.toString(), data });

        _ = try std.posix.write(self.writer, sendData);
    }

    pub fn receive(self: *Self) !struct { PChannelAction, []const u8 } {
        std.debug.print("debug: channel action receive loop started\n", .{});
        while (true) {
            var buffer: [1024]u8 = undefined;
            var rbuffer: []const u8 = "";
            const rsize = try std.posix.read(self.reader, &buffer);
            const rawData = buffer[0..rsize];
            var recvData = std.mem.tokenizeSequence(u8, rawData, ":");
            if (recvData.next()) |val| {
                const actVal = PChannelAction.fromString(val);
                if (actVal != PChannelAction.Undefined) {
                    if (recvData.next()) |dval| {
                        rbuffer = dval;
                    }

                    return .{ actVal, rbuffer };
                }
            }
        }
    }
};
