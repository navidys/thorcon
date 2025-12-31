const std = @import("std");

pub const PChannelAction = enum {
    Undefined,
    Wait,
    Init,
    InitDone,
    Exec,

    pub fn toString(self: PChannelAction) []const u8 {
        return switch (self) {
            .Wait => "wait",
            .Init => "init",
            .InitDone => "initdone",
            .Exec => "exec",
            else => "undefined",
        };
    }

    pub fn fromString(val: []const u8) PChannelAction {
        if (std.mem.eql(u8, val, "wait")) {
            return PChannelAction.Wait;
        }

        if (std.mem.eql(u8, val, "init")) {
            return PChannelAction.Init;
        }

        if (std.mem.eql(u8, val, "initdone")) {
            return PChannelAction.InitDone;
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

    label: []const u8,

    const Self = @This();

    pub fn init(label: []const u8) !Self {
        const fds = try std.posix.pipe();
        const reader = fds[0];
        const writer = fds[1];

        return Self{ .reader = reader, .writer = writer, .label = label };
    }

    pub fn send(self: *Self, value: PChannelAction) !void {
        std.debug.print("action {any} send to channel {s}\n", .{ value, self.label });

        _ = try std.posix.write(self.writer, value.toString());
    }

    pub fn receive(self: *Self) !PChannelAction {
        std.debug.print("action receive loop channel {s}\n", .{self.label});
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
