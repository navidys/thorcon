const std = @import("std");
const errors = @import("errors.zig");
const utils = @import("utils.zig");
const cntruntime = @import("runtime.zig");
const filesystem = @import("filesystem.zig");
const cntstate = @import("state.zig");
const namespace = @import("namespace.zig");
const process = @import("process.zig");
const ocispec = @import("ocispec");
const channel = @import("channel.zig");
const cleanup = @import("cleanup.zig");
const runtime = ocispec.runtime;
const channelAction = channel.PChannelAction;
const posix = std.posix;
const linux = std.os.linux;
const clone_flag = linux.CLONE;
const fs = std.fs;
const assert = std.debug.assert;

const DEFAULT_CLONE_STACKSIZE = 8 * 1024 * 1024;

// TODO check clone implementation
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

pub fn createContainer(name: []const u8, rootdir: []const u8, bundle: []const u8, spec: []const u8, noPivot: bool) !void {
    const runspec = try runtime.Spec.initFromFile(spec);
    const rootfs = try utils.getRootFSPath(bundle, runspec.root.path);

    std.log.debug("container name {s}", .{name});
    std.log.debug("root directory: {s}", .{rootdir});
    std.log.debug("bundle directory: {s}", .{bundle});
    std.log.debug("runtime config: {s}", .{spec});
    std.log.debug("rootfs: {s}", .{rootfs});

    // init and write state file
    var containerState = try cntstate.ContainerState.init(
        rootdir,
        bundle,
        rootfs,
        spec,
        noPivot,
    );

    if (!containerState.status.canCreate()) {
        std.log.err("cannot create container: {any}", .{errors.Error.ContainerInvalidStatus});
    }

    try containerState.setStatus(cntstate.ContainerStatus.Creating);
    try containerState.writeStateFile();

    // init container
    const initInfo = try initContainer(&containerState, runspec);

    containerState.commReader = initInfo[1];
    containerState.commWriter = initInfo[2];

    try containerState.setStatus(cntstate.ContainerStatus.Created);
    try containerState.writeStateFile();

    // write PID file
    try containerState.writePID(initInfo[0]);
}

fn initContainer(state: *cntstate.ContainerState, spec: runtime.Spec) !struct { usize, i32, i32 } {
    const pid = std.os.linux.getpid();
    std.log.debug("pid {} init container", .{pid});

    // TODO setup cgroup
    // TODO run hooks
    // TODO create NOTIFY SOCKET
    // TODO adjust oom if needed
    // TODO cleanup container (cgroup)

    var pcomm = try channel.PChannel.init();
    var ccomm = try channel.PChannel.init();

    const Args = std.meta.Tuple(&.{ []const u8, runtime.Spec, bool, *channel.PChannel, *channel.PChannel });
    const args: Args = .{
        state.rootfsDir,
        spec,
        state.noPivot,
        &pcomm,
        &ccomm,
    };

    var flags: u32 = 0;
    if (spec.linux) |rlinux| {
        if (rlinux.namespaces) |namespaces| {
            flags = @intCast(namespace.getUnshareFlags(pid, namespaces));
        }
    }

    std.log.debug("pid {} process cloning", .{pid});
    const childPID = try cntruntime.clone(flags, process.prepareAndExecute, args);

    // write user map
    std.log.debug("pid {} waiting for action {any}", .{ pid, channelAction.PreInitOK });
    while (true) {
        switch (try pcomm.receive()) {
            channelAction.PreInitOK => {
                break;
            },
            else => {},
        }
    }

    try writeMappings(pid, childPID, spec);

    std.log.debug("pid {} sending action {any}", .{ pid, channelAction.Init });

    try ccomm.send(channelAction.Init);

    std.log.debug("pid {} waiting for action {any}", .{ pid, channelAction.InitOK });
    while (true) {
        switch (try pcomm.receive()) {
            channelAction.InitOK => {
                break;
            },
            else => {},
        }
    }

    // switch (posix.E.init(posix.waitpid(@intCast(childPID), 0).status)) {
    //    .SUCCESS => std.log.debug("pid {} child cloned process has terminated", .{pid}),
    //    else => |err| {
    //        std.log.err("pid {} unexpectedErrno: {any}", .{ pid, err });
    //        return errors.Error.ProcessCloneError;
    //    },
    //}

    return .{ childPID, ccomm.reader, ccomm.writer };
}

fn writeMappings(pid: i32, tpid: usize, spec: runtime.Spec) !void {
    if (utils.isRootLess()) {
        if (spec.linux) |rlinux| {
            if (rlinux.uidMappings) |uidmappings| {
                try namespace.writeUidMappings(pid, tpid, uidmappings);
            }

            // TODO gid mapping is not working ???
            // if (rlinux.gidMappings) |gidmappings| {
            //    try namespace.writeGidMappings(pid, tpid, gidmappings);
            // }
        }
    }
}

fn callFn(comptime f: anytype, args: anytype) u8 {
    @call(.auto, f, args);

    return 0;
}
