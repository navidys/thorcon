const create = @import("create.zig");
const start = @import("start.zig");

pub const RunOptions = struct {
    name: []const u8,
    bundleDir: []const u8,
    spec: []const u8,
    noPivot: bool = false,
};

pub fn runContainer(rootDir: ?[]const u8, opts: RunOptions) !void {
    const createOptions = create.CreateOptions{
        .bundleDir = opts.bundleDir,
        .name = opts.name,
        .noPivot = opts.noPivot,
        .spec = opts.spec,
    };

    try create.createContainer(rootDir, &createOptions);
    try start.startContainer(rootDir, opts.name);
}
