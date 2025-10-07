const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const notification = @import("../notification.zig");

test "Windows backend COM initialization" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const windows = @import("../platform/windows.zig");

    var windows_backend = try windows.WindowsBackend.init(allocator);
    defer windows_backend.deinit();

    // Backend should report availability based on COM initialization
    const available = windows_backend.isAvailable();
    std.debug.print("Windows backend available: {}\n", .{available});

    // If available, should have capabilities
    if (available) {
        const caps = try windows_backend.getCapabilities(allocator);
        defer allocator.free(caps);
        try testing.expect(caps.len > 0);
        try testing.expect(std.mem.indexOf(u8, caps, "body") != null);
    }
}

test "Windows backend notification send" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const windows = @import("../platform/windows.zig");

    var windows_backend = try windows.WindowsBackend.init(allocator);
    defer windows_backend.deinit();

    if (!windows_backend.isAvailable()) {
        std.debug.print("Windows backend not available, skipping\n", .{});
        return error.SkipZigTest;
    }

    // Create test notification
    const notif = notification.Notification{
        .allocator = allocator,
        .title = "Windows Test",
        .message = "Testing WinRT Toast notification",
        .urgency = .normal,
        .timeout_ms = 3000,
    };

    // Send notification
    const id = try windows_backend.send(notif);
    try testing.expect(id > 0);
}

test "Windows backend XML generation" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const windows = @import("../platform/windows.zig");

    var windows_backend = try windows.WindowsBackend.init(allocator);
    defer windows_backend.deinit();

    // Create test notification with special characters
    const notif = notification.Notification{
        .allocator = allocator,
        .title = "Test & Title <xml>",
        .message = "Message with \"quotes\" & 'apostrophes'",
        .urgency = .critical,
        .timeout_ms = null,
    };

    // Generate XML
    var xml_buf: [4096]u8 = undefined;
    const xml = try windows_backend.buildToastXml(&xml_buf, notif);

    // Verify XML escaping
    try testing.expect(std.mem.indexOf(u8, xml, "&lt;xml&gt;") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "&quot;quotes&quot;") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "&apos;apostrophes&apos;") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "Test &amp; Title") != null);

    // Verify audio for critical urgency
    try testing.expect(std.mem.indexOf(u8, xml, "Looping.Alarm") != null);
}
