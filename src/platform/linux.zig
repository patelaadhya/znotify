const std = @import("std");
const Backend = @import("backend.zig").Backend;

/// Create Linux backend (stub for now)
pub fn createBackend(allocator: std.mem.Allocator) !Backend {
    _ = allocator;
    return error.NotImplemented;
}
