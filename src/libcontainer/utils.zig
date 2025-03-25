const std = @import("std");

pub fn isRootLess() bool {
    if (std.os.linux.getuid() == 0)
        return false;

    return true;
}
