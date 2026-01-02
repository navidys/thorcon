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

pub fn createContainer(name: []const u8, rootdir: []const u8, bundle: []const u8, spec: []const u8, noPivot: bool) !void {
    const runspec = try runtime.Spec.initFromFile(spec);

    // init container state
    var containerState = try initState(name, rootdir, bundle, spec, noPivot);

    // init container
    const initInfo = try initContainer(containerState, runspec);

    // update containier stat e
    try containerState.setCommFDs(initInfo[1], initInfo[2]);
    try containerState.setStatus(cntstate.ContainerStatus.Created);
    try containerState.writeStateFile();

    // write PID file
    try containerState.writePID(initInfo[0]);
}

fn initState(name: []const u8, rootdir: []const u8, bundle: []const u8, spec: []const u8, noPivot: bool) !*cntstate.ContainerState {
    const rootfs = try utils.getRootFSPath(bundle, spec.root.path);

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

        return errors.Error.ContainerInvalidStatus;
    }

    try containerState.setStatus(cntstate.ContainerStatus.Creating);
    try containerState.writeStateFile();

    return &containerState;
}

fn initContainer(state: *cntstate.ContainerState, spec: runtime.Spec) !struct { usize, i32, i32 } {
    const pid = std.os.linux.getpid();
    std.log.debug("pid {} init container", .{pid});

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
    const childPID = try clone.clone(flags, process.prepareAndExecute, args);

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
