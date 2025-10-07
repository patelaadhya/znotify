const std = @import("std");
const backend = @import("platform/backend.zig");
const notification = @import("notification.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Try to create platform-specific backend
    var platform_backend = backend.createPlatformBackend(allocator) catch |err| {
        std.debug.print("Platform backend failed: {}, using terminal\n", .{err});
        var term = try backend.createTerminalBackend(allocator);
        defer term.deinit();

        var notif = try notification.Notification.init(allocator, "Platform Test", "Using terminal fallback");
        defer notif.deinit();

        const id = try term.send(notif);
        std.debug.print("Notification sent with ID: {}\n", .{id});
        return;
    };
    defer platform_backend.deinit();

    var notif = try notification.Notification.init(allocator, "Platform Test", "Testing platform backend");
    defer notif.deinit();

    const id = try platform_backend.send(notif);
    std.debug.print("Notification sent with ID: {}\n", .{id});

    const caps = try platform_backend.getCapabilities(allocator);
    defer allocator.free(caps);
    std.debug.print("Backend capabilities: {s}\n", .{caps});
}
