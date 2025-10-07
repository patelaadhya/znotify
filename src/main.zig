const std = @import("std");
const backend = @import("platform/backend.zig");
const notification = @import("notification.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const platform = backend.Platform.detect();
    std.debug.print("Detected platform: {s}\n", .{platform.toString()});

    // Test terminal backend
    var term_backend = try backend.createTerminalBackend(allocator);
    defer term_backend.deinit();

    var notif = try notification.Notification.init(allocator, "Test", "Terminal backend test");
    defer notif.deinit();
    notif.setUrgency(.critical);

    const id = try term_backend.send(notif);
    std.debug.print("Notification sent with ID: {}\n", .{id});

    try term_backend.close(id);
}
