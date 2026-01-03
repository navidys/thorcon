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
    pcomm: *channel.PChannel,
    ccomm: *channel.PChannel,
};

pub fn create(pid: i32, opts: *RuntimeOptions) !void {

    // init container state
    var containerState = try initState(pid, opts);

    // init container
    const cid = try initContainer(pid, opts);

    // update containier start
    try containerState.setStatus(cntstate.ContainerStatus.Created);
    try containerState.writeStateFile();

    // write PID file
    try containerState.writePID(cid);
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
        opts.ccomm.reader,
        opts.ccomm.writer,
    );

    try containerState.setStatus(cntstate.ContainerStatus.Creating);
    try containerState.writeStateFile();

    return &containerState;
}

fn initContainer(pid: i32, opts: *RuntimeOptions) !usize {
    std.log.debug("pid {} init container", .{pid});

    const Args = std.meta.Tuple(&.{*RuntimeOptions});
    const args: Args = .{opts};

    std.log.debug("pid {} process cloning", .{pid});
    const childPID = try clone.clone(0, process.processPrep, args);

    // write user map
    std.log.debug("pid {} waiting for action {any}", .{ pid, channelAction.UserMapRequest });
    while (true) {
        switch (try opts.pcomm.receive()) {
            channelAction.UserMapRequest => {
                try namespace.writeMappings(pid, childPID, opts.runtimeSpec);

                std.log.debug("pid {} sending action {any}", .{ pid, channelAction.UserMapOK });

                try opts.ccomm.send(channelAction.UserMapOK);

                break;
            },
            else => {},
        }
    }

    std.log.debug("pid {} waiting for action {any}", .{ pid, channelAction.Ready });
    while (true) {
        switch (try opts.pcomm.receive()) {
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

    return childPID;
}
