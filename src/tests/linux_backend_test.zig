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

    // Test short timeout notification
    const notif = notification.Notification{
        .allocator = allocator,
        .title = "Timeout Test",
        .message = "Testing timeout",
        .urgency = .normal,
        .timeout_ms = 500,
    };

    const id = try backend.send(notif);
    try testing.expect(id > 0);
    try backend.close(id);
}

test "Linux backend capability checking" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    const linux = @import("../platform/linux.zig");

    var backend = try linux.LinuxBackend.init(allocator);
    defer backend.deinit();

    if (!backend.isAvailable()) {
        return error.SkipZigTest;
    }

    // Test hasCapability with known capability
    const has_body = try backend.hasCapability(allocator, "body");
    try testing.expect(has_body);

    // Test hasCapability with non-existent capability
    const has_fake = try backend.hasCapability(allocator, "fake-capability-xyz");
    try testing.expect(!has_fake);

    // Test helper functions (may vary by daemon)
    _ = try backend.supportsActions(allocator);
    _ = try backend.supportsIcons(allocator);
    _ = try backend.supportsBodyMarkup(allocator);
}

test "Linux backend icon theme name support" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    const linux = @import("../platform/linux.zig");

    var backend = try linux.LinuxBackend.init(allocator);
    defer backend.deinit();

    if (!backend.isAvailable()) {
        return error.SkipZigTest;
    }

    // Check if icons are supported
    const supports_icons = try backend.supportsIcons(allocator);
    if (!supports_icons) {
        std.debug.print("Icons not supported by daemon, skipping\n", .{});
        return error.SkipZigTest;
    }

    // Test with icon theme name (builtin icon)
    const notif = notification.Notification{
        .allocator = allocator,
        .title = "Icon Test",
        .message = "Testing icon theme name",
        .urgency = .normal,
        .timeout_ms = 500,
        .icon = .{ .builtin = .info },
    };

    const id = try backend.send(notif);
    try testing.expect(id > 0);
    try backend.close(id);
}

test "Linux backend file path icon support" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    const linux = @import("../platform/linux.zig");

    var backend = try linux.LinuxBackend.init(allocator);
    defer backend.deinit();

    if (!backend.isAvailable()) {
        return error.SkipZigTest;
    }

    // Check if icons are supported
    const supports_icons = try backend.supportsIcons(allocator);
    if (!supports_icons) {
        std.debug.print("Icons not supported by daemon, skipping\n", .{});
        return error.SkipZigTest;
    }

    // Test with file path (using a common system icon)
    const notif = notification.Notification{
        .allocator = allocator,
        .title = "Icon Test",
        .message = "Testing file path icon",
        .urgency = .normal,
        .timeout_ms = 500,
        .icon = .{ .file_path = "/usr/share/icons/hicolor/48x48/apps/firefox.png" },
    };

    const id = try backend.send(notif);
    try testing.expect(id > 0);
    try backend.close(id);
}

test "Linux backend notification updates with replaces_id" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    const linux = @import("../platform/linux.zig");

    var backend = try linux.LinuxBackend.init(allocator);
    defer backend.deinit();

    if (!backend.isAvailable()) {
        return error.SkipZigTest;
    }

    // Send initial notification
    const initial = notification.Notification{
        .allocator = allocator,
        .title = "Update Test",
        .message = "Initial message",
        .urgency = .normal,
        .timeout_ms = 0, // Persistent
    };

    const id = try backend.send(initial);
    try testing.expect(id > 0);

    // Update the notification using replaces_id
    const updated = notification.Notification{
        .allocator = allocator,
        .title = "Update Test",
        .message = "Updated message",
        .urgency = .critical,
        .timeout_ms = 500,
        .replace_id = id,
    };

    const new_id = try backend.send(updated);
    // When replacing, the daemon should return the same ID
    try testing.expectEqual(id, new_id);

    try backend.close(new_id);
}
