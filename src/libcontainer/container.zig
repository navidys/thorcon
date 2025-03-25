const state = @import("state.zig");

pub const Container = struct {
    state: state.ContainerState,
    root: []const u8 = "/run/thorcon/",

    pub fn init(cid: []const u8, cstatus: state.ContainerStatus, cpid: ?i32, cbundle: []const u8, root: []const u8) Container {
        const cstate = state.ContainerState.init(cid, cstatus, cpid, cbundle);

        return Container{
            .root = root,
            .state = cstate,
        };
    }

    pub fn load(root: []const u8) !Container {
        const cstate = try state.ContainerState.load(root);

        // TODO refresh state

        const container = Container{
            .state = cstate,
            .root = root,
        };

        return container;
    }

    pub fn save(self: @This()) !void {
        try self.state.save(self.root);
    }

    pub fn id(self: @This()) []const u8 {
        return self.state.id;
    }

    pub fn canStart(self: @This()) bool {
        return self.state.status.canStart();
    }

    pub fn canKill(self: @This()) bool {
        return self.state.status.canKill();
    }

    pub fn canDelete(self: @This()) bool {
        return self.state.status.canDelete();
    }

    pub fn canExec(self: @This()) bool {
        return self.state.status.canExec();
    }

    pub fn canPause(self: @This()) bool {
        return self.state.status.canPause();
    }

    pub fn canResume(self: @This()) bool {
        return self.state.status.canResume();
    }

    pub fn bundle(self: @This()) []const u8 {
        return self.state.bundle;
    }

    pub fn pid(self: @This()) ?i32 {
        return self.state.pid;
    }

    pub fn created(self: @This()) ?[]const u8 {
        return self.state.created;
    }

    pub fn creator(self: @This()) ?[]const u8 {
        return self.state.creator;
    }

    pub fn systemd(self: @This()) bool {
        return self.state.useSystemd;
    }

    pub fn status(self: @This()) state.ContainerStatus {
        return self.state.status;
    }

    pub fn cleanupIntelRdtSubDir(self: @This()) bool {
        return self.state.cleanupIntelRdtSubDir;
    }
};
