const std = @import("std");
const errors = @import("errors.zig");
const ocispec = @import("ocispec");
const utils = @import("utils.zig");
const cntruntime = @import("runtime.zig");
const filesystem = @import("filesystem.zig");
const cntstate = @import("state.zig");
const cntlist = @import("list.zig");
const channel = @import("channel.zig");
const namespace = @import("namespace.zig");
const process = @import("process.zig");
const list = @import("list.zig");
const runtime = ocispec.runtime;
const channelAction = channel.PChannelAction;
const posix = std.posix;

pub const CreateOptions = struct {
    name: []const u8,
    bundleDir: []const u8,
    spec: []const u8,
    noPivot: bool = false,
};

pub fn createContainer(rootDir: ?[]const u8, opts: *const CreateOptions) !void {
    var bundledir: []const u8 = ".";
    var cntspec: []const u8 = "config.json";

    if (opts.name.len == 0) {
        return errors.Error.InvalidContainerName;
    }

    if (opts.bundleDir.len != 0) {
        bundledir = try utils.canonicalPath(opts.bundleDir);
    }

    if (opts.spec.len != 0) {
        cntspec = opts.spec;
    } else {
        cntspec = try std.mem.concat(std.heap.page_allocator, u8, &.{ bundledir, "/", cntspec });
    }

    const rootdir = try filesystem.initRootPath(rootDir, null);
    const cntRootDir = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ rootdir, opts.name });

    std.log.debug("container name {s}", .{opts.name});
    std.log.debug("container root dir {s}", .{cntRootDir});

    const cntStateResult = cntstate.ContainerState.getContainerState(cntRootDir);
    var canCreate = false;

    if (cntStateResult) |result| {
        if (!result.status.canCreate()) {
            return errors.Error.ContainerInvalidStatus;
        }

        canCreate = true;
    } else |err| {
        if (err != std.fs.File.OpenError.FileNotFound) {
            return err;
        }

        canCreate = true;
    }

    if (canCreate) {
        try create(opts.name, rootDir, bundledir, cntspec, opts.noPivot);
    }
}

fn create(name: []const u8, rootDir: ?[]const u8, bundle: []const u8, spec: []const u8, noPivot: bool) !void {
    const runspec = try runtime.Spec.initFromFile(spec);
    const rootfs = try utils.getRootFSPath(bundle, runspec.root.path);
    const cntRootDir = try filesystem.initRootPath(rootDir, name);

    std.log.debug("root directory: {s}", .{cntRootDir});
    std.log.debug("bundle directory: {s}", .{bundle});
    std.log.debug("runtime config: {s}", .{spec});
    std.log.debug("rootfs: {s}", .{rootfs});

    // init and write state file
    var containerState = try cntstate.ContainerState.init(
        cntRootDir,
        bundle,
        rootfs,
        spec,
        noPivot,
    );

    try containerState.lock();
    defer containerState.unlock() catch |err| {
        std.log.err("container state unlock: {any}", .{err});
    };

    if (!containerState.status.canCreate()) {
        std.log.err("cannot create container: {any}", .{errors.Error.ContainerInvalidStatus});
    }

    try containerState.writeStateFile();

    // init container
    const fds = try initContainer(&containerState, runspec);

    containerState.status = cntstate.ContainerStatus.Created;
    containerState.commReader = fds[0];
    containerState.commWriter = fds[1];
    try containerState.writeStateFile();
}

fn initContainer(state: *cntstate.ContainerState, spec: runtime.Spec) !struct { i32, i32 } {
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
    const childPID = try process.clone(flags, cntruntime.prepareAndExecute, args);

    // write PID file
    try state.writePID(childPID);

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

    return .{ ccomm.reader, ccomm.writer };
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
