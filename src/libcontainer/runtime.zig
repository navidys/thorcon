const std = @import("std");
const errors = @import("errors.zig");
const utils = @import("utils.zig");
const filesystem = @import("filesystem.zig");
const cntstate = @import("state.zig");
const namespace = @import("namespace.zig");
const process = @import("process.zig");
const ocispec = @import("ocispec");
const channel = @import("channel.zig");
const cleanup = @import("cleanup.zig");
const clone = @import("clone.zig");
const runtime = ocispec.runtime;
const channelAction = channel.PChannelAction;
const posix = std.posix;
const linux = std.os.linux;
const clone_flag = linux.CLONE;
const fs = std.fs;
const assert = std.debug.assert;

pub const RuntimeOptions = struct {
    name: []const u8,
    bundle: []const u8,
    rootdir: []const u8,
    rootfs: []const u8,
    spec: []const u8,
    noPivot: bool,
    runtimeSpec: runtime.Spec,
};

pub fn create(pid: i32, opts: *RuntimeOptions) !void {
    // init container state

    var containerState = try initState(pid, opts);

    // init container
    const initInfo = try initContainer(pid, opts.rootfs, opts.noPivot, opts.runtimeSpec);

    // update containier start
    try containerState.setCommFDs(initInfo[1], initInfo[2]);
    try containerState.setStatus(cntstate.ContainerStatus.Created);
    try containerState.writeStateFile();

    // write PID file
    try containerState.writePID(initInfo[0]);
}

fn initState(pid: i32, opts: *RuntimeOptions) !*cntstate.ContainerState {
    // init and write state file
    var containerState = try cntstate.ContainerState.init(
        pid,
        opts.rootdir,
        opts.rootdir,
        opts.bundle,
        opts.rootfs,
        opts.noPivot,
    );

    try containerState.setStatus(cntstate.ContainerStatus.Creating);
    try containerState.writeStateFile();

    return &containerState;
}

fn initContainer(pid: i32, rootfs: []const u8, noPivot: bool, spec: runtime.Spec) !struct { usize, i32, i32 } {
    std.log.debug("pid {} init container", .{pid});

    var pcomm = try channel.PChannel.init();
    var ccomm = try channel.PChannel.init();

    const Args = std.meta.Tuple(&.{ []const u8, runtime.Spec, bool, *channel.PChannel, *channel.PChannel });
    const args: Args = .{
        rootfs,
        spec,
        noPivot,
        &pcomm,
        &ccomm,
    };

    // var flags: u32 = 0;
    // if (spec.linux) |rlinux| {
    //    if (rlinux.namespaces) |namespaces| {
    //        flags = @intCast(namespace.getUnshareFlags(pid, namespaces));
    //    }
    //}

    std.log.debug("pid {} process cloning", .{pid});
    const childPID = try clone.clone(0, process.prepareAndExecute, args);

    // write user map
    std.log.debug("pid {} waiting for action {any}", .{ pid, channelAction.UserMapRequest });
    while (true) {
        switch (try pcomm.receive()) {
            channelAction.UserMapRequest => {
                try namespace.writeMappings(pid, childPID, spec);

                std.log.debug("pid {} sending action {any}", .{ pid, channelAction.UserMapOK });

                try ccomm.send(channelAction.UserMapOK);

                break;
            },
            else => {},
        }
    }

    std.log.debug("pid {} waiting for action {any}", .{ pid, channelAction.Ready });
    while (true) {
        switch (try pcomm.receive()) {
            channelAction.Ready => {
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
