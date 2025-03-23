const std = @import("std");
const utils = @import("utils.zig");
const ocispec = @import("ocispec");
const runtime = ocispec.runtime;

pub const SpecOptions = struct {
    rootless: ?bool = null,
    bundleDir: []const u8,
    file: []const u8,
};

pub fn generateSpec(opts: *const SpecOptions) !void {
    const file_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ opts.bundleDir, opts.file });
    const spec_path = try utils.canonicalPath(file_path);

    std.log.debug("rootless: {any}", .{opts.rootless});
    std.log.debug("runtime config: {s}", .{spec_path});

    if (opts.rootless.?) {
        const spec = try getSpec(true);
        return spec.toFilePretty(spec_path);
    }

    const spec = try getSpec(false);

    return spec.toFilePretty(spec_path);
}

fn getSpec(rootless: bool) !*runtime.Spec {
    // process
    var process_rlimit = std.ArrayList(runtime.PosixRlimit).init(std.heap.page_allocator);
    try process_rlimit.append(runtime.PosixRlimit{
        .type = runtime.PosixRlimitType.RlimitNofile,
        .hard = 1024,
        .soft = 1024,
    });

    defer process_rlimit.deinit();

    var process_args = std.ArrayList([]const u8).init(std.heap.page_allocator);

    defer process_args.deinit();
    try process_args.append("sh");

    var process_env = std.ArrayList([]const u8).init(std.heap.page_allocator);

    defer process_env.deinit();
    try process_env.append("PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
    try process_env.append("TERM=xterm");
    const process_cap = try getSpecProcessCap();

    // linux spec
    var linux_resource_devices = std.ArrayList(runtime.LinuxDeviceCgroup).init(std.heap.page_allocator);
    defer linux_resource_devices.deinit();

    try linux_resource_devices.append(runtime.LinuxDeviceCgroup{ .allow = false, .access = "rwm" });

    const mount_points = try getSpecMountPoints(rootless);
    const linux_namespace = try getSpecNamespaces(rootless);
    const linux_masked_path = try getSpecMaskedPath();
    const linux_readonly_path = try getSpecReadonlyPath();
    const uid_mappings = try getUIDMappings(rootless);
    const gid_mappings = try getGIDMappings(rootless);

    var spec = runtime.Spec{
        .process = runtime.Process{
            .terminal = true,
            .user = runtime.User{
                .uid = 0,
                .gid = 0,
            },
            .args = try process_args.toOwnedSlice(),
            .cwd = "/",
            .env = try process_env.toOwnedSlice(),
            .capabilities = process_cap,
            .noNewPrivileges = true,
            .rlimits = try process_rlimit.toOwnedSlice(),
        },
        .linux = runtime.Linux{
            .resources = runtime.LinuxResources{
                .devices = try linux_resource_devices.toOwnedSlice(),
            },
            .uidMappings = uid_mappings,
            .gidMappings = gid_mappings,
            .namespaces = linux_namespace,
            .maskedPaths = linux_masked_path,
            .readonlyPaths = linux_readonly_path,
        },
        .mounts = mount_points,
        .root = runtime.Root{
            .path = "rootfs",
            .readonly = true,
        },
        .hostname = "thorcon",
    };

    return &spec;
}

fn getUIDMappings(rootless: bool) !?[]runtime.LinuxIdMapping {
    if (!rootless) {
        return null;
    }

    var uid_mappings = std.ArrayList(runtime.LinuxIdMapping).init(std.heap.page_allocator);

    try uid_mappings.append(runtime.LinuxIdMapping{
        .hostID = std.os.linux.getuid(),
        .containerID = 0,
        .size = 1,
    });

    return try uid_mappings.toOwnedSlice();
}

fn getGIDMappings(rootless: bool) !?[]runtime.LinuxIdMapping {
    if (!rootless) {
        return null;
    }

    var gid_mappings = std.ArrayList(runtime.LinuxIdMapping).init(std.heap.page_allocator);

    try gid_mappings.append(runtime.LinuxIdMapping{
        .hostID = std.os.linux.getgid(),
        .containerID = 0,
        .size = 1,
    });

    return try gid_mappings.toOwnedSlice();
}

fn getSpecProcessCap() !runtime.LinuxCapabilities {
    var bounding = std.ArrayList(runtime.Capability).init(std.heap.page_allocator);

    defer bounding.deinit();
    try bounding.append(runtime.Capability.AuditWrite);
    try bounding.append(runtime.Capability.Kill);
    try bounding.append(runtime.Capability.NetBindService);

    var effective = std.ArrayList(runtime.Capability).init(std.heap.page_allocator);

    defer effective.deinit();
    try effective.append(runtime.Capability.AuditWrite);
    try effective.append(runtime.Capability.Kill);
    try effective.append(runtime.Capability.NetBindService);

    var inheritable = std.ArrayList(runtime.Capability).init(std.heap.page_allocator);

    defer inheritable.deinit();

    var permitted = std.ArrayList(runtime.Capability).init(std.heap.page_allocator);

    defer permitted.deinit();
    try permitted.append(runtime.Capability.AuditWrite);
    try permitted.append(runtime.Capability.Kill);
    try permitted.append(runtime.Capability.NetBindService);

    var ambient = std.ArrayList(runtime.Capability).init(std.heap.page_allocator);

    defer ambient.deinit();
    try ambient.append(runtime.Capability.AuditWrite);
    try ambient.append(runtime.Capability.Kill);
    try ambient.append(runtime.Capability.NetBindService);

    return runtime.LinuxCapabilities{
        .bounding = try bounding.toOwnedSlice(),
        .effective = try effective.toOwnedSlice(),
        .inheritable = try inheritable.toOwnedSlice(),
        .permitted = try permitted.toOwnedSlice(),
        .ambient = try ambient.toOwnedSlice(),
    };
}

fn getSpecReadonlyPath() ![][]const u8 {
    var linux_readonly_path = std.ArrayList([]const u8).init(std.heap.page_allocator);

    defer linux_readonly_path.deinit();
    try linux_readonly_path.append("/proc/bus");
    try linux_readonly_path.append("/proc/fs");
    try linux_readonly_path.append("/proc/irq");
    try linux_readonly_path.append("/proc/sys");
    try linux_readonly_path.append("/proc/sysrq-trigger");

    return try linux_readonly_path.toOwnedSlice();
}

fn getSpecMaskedPath() ![][]const u8 {
    var linux_masked_path = std.ArrayList([]const u8).init(std.heap.page_allocator);

    defer linux_masked_path.deinit();
    try linux_masked_path.append("/proc/acpi");
    try linux_masked_path.append("/proc/asound");
    try linux_masked_path.append("/proc/kcore");
    try linux_masked_path.append("/proc/keys");
    try linux_masked_path.append("/proc/latency_stats");
    try linux_masked_path.append("/proc/timer_list");
    try linux_masked_path.append("/proc/timer_stats");
    try linux_masked_path.append("/proc/sched_debug");
    try linux_masked_path.append("/proc/scsi");
    try linux_masked_path.append("/sys/firmware");

    return try linux_masked_path.toOwnedSlice();
}

fn getSpecNamespaces(rootless: bool) ![]runtime.LinuxNamespace {
    var linux_namespace = std.ArrayList(runtime.LinuxNamespace).init(std.heap.page_allocator);

    defer linux_namespace.deinit();
    try linux_namespace.append(runtime.LinuxNamespace{ .type = runtime.LinuxNamespaceType.Pid });
    try linux_namespace.append(runtime.LinuxNamespace{ .type = runtime.LinuxNamespaceType.Network });
    try linux_namespace.append(runtime.LinuxNamespace{ .type = runtime.LinuxNamespaceType.Ipc });
    try linux_namespace.append(runtime.LinuxNamespace{ .type = runtime.LinuxNamespaceType.Uts });
    try linux_namespace.append(runtime.LinuxNamespace{ .type = runtime.LinuxNamespaceType.Mount });
    try linux_namespace.append(runtime.LinuxNamespace{ .type = runtime.LinuxNamespaceType.Cgroup });

    if (rootless) {
        try linux_namespace.append(runtime.LinuxNamespace{ .type = runtime.LinuxNamespaceType.User });
    }

    return try linux_namespace.toOwnedSlice();
}

fn getSpecMountPoints(rootless: bool) ![]runtime.Mount {
    var mount_points = std.ArrayList(runtime.Mount).init(std.heap.page_allocator);

    defer mount_points.deinit();

    // proc
    try mount_points.append(runtime.Mount{ .destination = "/proc", .type = "proc", .source = "proc" });

    // dev
    var devMountOpts = std.ArrayList([]const u8).init(std.heap.page_allocator);

    defer devMountOpts.deinit();
    try devMountOpts.append("nosuid");
    try devMountOpts.append("strictatime");
    try devMountOpts.append("mode=755");
    try devMountOpts.append("size=65536k");
    try mount_points.append(runtime.Mount{
        .destination = "/dev",
        .type = "tmpfs",
        .source = "tmpfs",
        .options = try devMountOpts.toOwnedSlice(),
    });

    // shm
    var shmMountOpts = std.ArrayList([]const u8).init(std.heap.page_allocator);

    defer shmMountOpts.deinit();
    try shmMountOpts.append("nosuid");
    try shmMountOpts.append("noexec");
    try shmMountOpts.append("nodev");
    try shmMountOpts.append("mode=1777");
    try shmMountOpts.append("size=65536k");
    try mount_points.append(runtime.Mount{
        .destination = "/dev/shm",
        .type = "tmpfs",
        .source = "shm",
        .options = try shmMountOpts.toOwnedSlice(),
    });

    // mqueue
    var mqueueMountOpts = std.ArrayList([]const u8).init(std.heap.page_allocator);

    defer mqueueMountOpts.deinit();
    try mqueueMountOpts.append("nosuid");
    try mqueueMountOpts.append("noexec");
    try mqueueMountOpts.append("nodev");
    try mount_points.append(runtime.Mount{
        .destination = "/dev/mqueue",
        .type = "mqueue",
        .source = "mqueue",
        .options = try mqueueMountOpts.toOwnedSlice(),
    });

    // sys
    var sysMountOpts = std.ArrayList([]const u8).init(std.heap.page_allocator);

    defer sysMountOpts.deinit();
    try sysMountOpts.append("nosuid");
    try sysMountOpts.append("noexec");
    try sysMountOpts.append("nodev");
    try sysMountOpts.append("ro");
    try mount_points.append(runtime.Mount{
        .destination = "/sys",
        .type = "sysfs",
        .source = "sysfs",
        .options = try sysMountOpts.toOwnedSlice(),
    });

    // cgroup
    var cgroupMountOpts = std.ArrayList([]const u8).init(std.heap.page_allocator);

    defer cgroupMountOpts.deinit();
    try cgroupMountOpts.append("nosuid");
    try cgroupMountOpts.append("noexec");
    try cgroupMountOpts.append("nodev");
    try cgroupMountOpts.append("relatime");
    try cgroupMountOpts.append("ro");
    try mount_points.append(runtime.Mount{
        .destination = "/sys/fs/cgroup",
        .type = "cgroup",
        .source = "cgroup",
        .options = try cgroupMountOpts.toOwnedSlice(),
    });

    if (rootless) {
        // /dev/pts (rootless)
        var ptsMountOpts = std.ArrayList([]const u8).init(std.heap.page_allocator);

        defer ptsMountOpts.deinit();
        try ptsMountOpts.append("nosuid");
        try ptsMountOpts.append("noexec");
        try ptsMountOpts.append("newinstance");
        try ptsMountOpts.append("ptmxmode=0666");
        try ptsMountOpts.append("mode=0620");

        try mount_points.append(runtime.Mount{
            .destination = "/dev/pts",
            .type = "devpts",
            .source = "devpts",
            .options = try ptsMountOpts.toOwnedSlice(),
        });
    } else {
        // /dev/pts
        var ptsMountOpts = std.ArrayList([]const u8).init(std.heap.page_allocator);

        defer ptsMountOpts.deinit();
        try ptsMountOpts.append("nosuid");
        try ptsMountOpts.append("noexec");
        try ptsMountOpts.append("newinstance");
        try ptsMountOpts.append("ptmxmode=0666");
        try ptsMountOpts.append("mode=0620");
        try ptsMountOpts.append("gid=5");

        try mount_points.append(runtime.Mount{
            .destination = "/dev/pts",
            .type = "devpts",
            .source = "devpts",
            .options = try ptsMountOpts.toOwnedSlice(),
        });
    }

    return try mount_points.toOwnedSlice();
}
