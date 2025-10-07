const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const notification = @import("../notification.zig");

test "Linux backend D-Bus connection" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    const linux = @import("../platform/linux.zig");

    var linux_backend = try linux.LinuxBackend.init(allocator);
    defer linux_backend.deinit();

    // Backend should report availability based on D-Bus connection
    const available = linux_backend.isAvailable();
    std.debug.print("Linux backend available: {}\n", .{available});

    // If available, should have capabilities
    if (available) {
        const caps = try linux_backend.getCapabilities(allocator);
        defer allocator.free(caps);
        try testing.expect(caps.len > 0);
        try testing.expect(std.mem.indexOf(u8, caps, "body") != null);
    }
}

test "Linux backend notification send" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    const linux = @import("../platform/linux.zig");

    var linux_backend = try linux.LinuxBackend.init(allocator);
    defer linux_backend.deinit();

    if (!linux_backend.isAvailable()) {
        std.debug.print("D-Bus not available, skipping\n", .{});
        return error.SkipZigTest;
    }

    // Create test notification
    const notif = notification.Notification{
        .allocator = allocator,
        .title = "Linux Test",
        .message = "Testing D-Bus notification",
        .urgency = .normal,
        .timeout_ms = 3000,
    };

    // Send notification
    const id = try linux_backend.send(notif);
    try testing.expect(id > 0);

    // Test close notification
    try linux_backend.close(id);
}

test "Linux backend GetCapabilities parsing" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    const linux = @import("../platform/linux.zig");

    var backend = try linux.LinuxBackend.init(allocator);
    defer backend.deinit();

    if (!backend.isAvailable()) {
        return error.SkipZigTest;
    }

    const caps = try backend.getCapabilities(allocator);
    defer allocator.free(caps);

    // Should return comma-separated capability list
    try testing.expect(caps.len > 0);

    // Common capabilities that should be present
    const has_body = std.mem.indexOf(u8, caps, "body") != null;
    try testing.expect(has_body);
}

test "Linux backend urgency levels" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    const linux = @import("../platform/linux.zig");

    var backend = try linux.LinuxBackend.init(allocator);
    defer backend.deinit();

    if (!backend.isAvailable()) {
        return error.SkipZigTest;
    }

    // Test critical urgency (most important to verify)
    const notif = notification.Notification{
        .allocator = allocator,
        .title = "Urgency Test",
        .message = "Testing critical urgency",
        .urgency = .critical,
        .timeout_ms = 500,
    };

    const id = try backend.send(notif);
    try testing.expect(id > 0);
    try backend.close(id);
}

test "Linux backend timeout handling" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    const linux = @import("../platform/linux.zig");

    var backend = try linux.LinuxBackend.init(allocator);
    defer backend.deinit();

    if (!backend.isAvailable()) {
        return error.SkipZigTest;
    }

    // Test persistent notification (timeout = 0)
    const notif = notification.Notification{
        .allocator = allocator,
        .title = "Timeout Test",
        .message = "Testing persistent notification",
        .urgency = .normal,
        .timeout_ms = 0,
    };

    const id = try backend.send(notif);
    try testing.expect(id > 0);
    try backend.close(id);
}
