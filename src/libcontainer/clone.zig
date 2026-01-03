const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const clone_flag = linux.CLONE;
const fs = std.fs;
const assert = std.debug.assert;

const DEFAULT_CLONE_STACKSIZE = 8 * 1024 * 1024;

pub fn clone(flags: u32, f: anytype, args: anytype) !usize {
    const page_size = std.heap.pageSize();
    const Args = @TypeOf(args);

    const Instance = struct {
        fn_args: Args,

        fn entryFn(raw_arg: usize) callconv(.c) u8 {
            const self = @as(*@This(), @ptrFromInt(raw_arg));

            return callFn(f, self.fn_args);
        }
    };

    var guard_offset: usize = undefined;
    var stack_offset: usize = undefined;
    var instance_offset: usize = undefined;

    const map_bytes = blk: {
        var bytes: usize = page_size;
        guard_offset = bytes;

        bytes += @max(page_size, DEFAULT_CLONE_STACKSIZE);
        bytes = std.mem.alignForward(usize, bytes, page_size);
        stack_offset = bytes;

        bytes = std.mem.alignForward(usize, bytes, @alignOf(Instance));
        instance_offset = bytes;
        bytes += @sizeOf(Instance);

        bytes = std.mem.alignForward(usize, bytes, page_size);
        break :blk bytes;
    };

    const mapped = posix.mmap(
        null,
        map_bytes,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .STACK = true },
        -1,
        0,
    ) catch |err| switch (err) {
        error.MemoryMappingNotSupported => unreachable,
        error.AccessDenied => unreachable,
        error.PermissionDenied => unreachable,
        error.ProcessFdQuotaExceeded => unreachable,
        error.SystemFdQuotaExceeded => unreachable,
        error.MappingAlreadyExists => unreachable,
        else => |e| return e,
    };
    assert(mapped.len >= map_bytes);

    errdefer posix.munmap(mapped);

    // map everything but the guard page as read/write
    posix.mprotect(
        @alignCast(mapped[guard_offset..]),
        posix.PROT.READ | posix.PROT.WRITE,
    ) catch |err| switch (err) {
        error.AccessDenied => unreachable,
        else => |e| return e,
    };

    const instance: *Instance = @ptrCast(@alignCast(&mapped[instance_offset]));
    instance.* = .{
        .fn_args = args,
    };

    const pid = linux.clone(
        Instance.entryFn,
        @intFromPtr(&mapped[stack_offset]),
        flags | linux.SIG.CHLD,
        @intFromPtr(instance),
        null,
        0,
        null,
    );

    const ppid = std.os.linux.getpid();

    switch (linux.E.init(pid)) {
        .SUCCESS => std.log.debug("pid {} child clone pid {d}", .{ ppid, pid }),
        else => |err| {
            std.log.debug("pid {} unexpectedErrno: {any}", .{ ppid, err });
            unreachable;
        },
    }

    return pid;
}

fn callFn(comptime f: anytype, args: anytype) u8 {
    @call(.auto, f, args);

    return 0;
}
