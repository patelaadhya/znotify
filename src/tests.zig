const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

test "build system works" {
    try testing.expect(true);
}

const notification = @import("notification.zig");

test "Urgency enum conversion" {
    try testing.expectEqual(notification.Urgency.low, try notification.Urgency.fromString("low"));
    try testing.expectEqual(notification.Urgency.critical, try notification.Urgency.fromString("critical"));
    try testing.expectError(error.InvalidUrgency, notification.Urgency.fromString("invalid"));
}

test "Notification creation and modification" {
    const allocator = testing.allocator;

    var notif = try notification.Notification.init(allocator, "Title", "Message");
    defer notif.deinit();

    try testing.expectEqualStrings("Title", notif.title);
    try testing.expectEqualStrings("Message", notif.message);
    try testing.expectEqual(notification.Urgency.normal, notif.urgency);

    notif.setUrgency(.critical);
    try testing.expectEqual(notification.Urgency.critical, notif.urgency);
}

test "Notification builder" {
    const allocator = testing.allocator;

    var builder = try notification.NotificationBuilder.init(allocator, "Test", "Builder");
    var notif = builder.urgency(.low).timeout(1000).build();
    defer notif.deinit();

    try testing.expectEqual(notification.Urgency.low, notif.urgency);
    try testing.expectEqual(@as(?u32, 1000), notif.timeout_ms);
}

const errors = @import("errors.zig");

test "Error exit codes" {
    try testing.expectEqual(@as(u8, 10), errors.getExitCode(errors.ZNotifyError.PlatformNotSupported));
    try testing.expectEqual(@as(u8, 20), errors.getExitCode(errors.ZNotifyError.InvalidArgument));
    try testing.expectEqual(@as(u8, 30), errors.getExitCode(errors.ZNotifyError.NotificationFailed));
}

test "Error suggestions" {
    const suggestion = errors.getRemediationSuggestion(errors.ZNotifyError.InvalidUrgency);
    try testing.expect(suggestion != null);
    try testing.expect(std.mem.indexOf(u8, suggestion.?, "low, normal, or critical") != null);
}

test "Error context formatting" {
    const context = errors.ErrorContext{
        .error_type = errors.ZNotifyError.InvalidIconPath,
        .message = "Test error",
        .details = "Additional details",
        .platform_code = 42,
    };

    // Test that context fields are accessible
    try testing.expectEqualStrings("Test error", context.message);
    try testing.expectEqualStrings("Additional details", context.details.?);
    try testing.expectEqual(@as(i32, 42), context.platform_code.?);
    try testing.expectEqual(errors.ZNotifyError.InvalidIconPath, context.error_type);
}

const cli = @import("cli.zig");

test "Parse basic arguments" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "znotify", "Title", "Message" };

    var parser = cli.ArgParser.init(allocator, &args);
    const config = try parser.parse();

    try testing.expectEqualStrings("Title", config.title.?);
    try testing.expectEqualStrings("Message", config.message.?);
}

test "Parse short options" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "znotify", "-u", "critical", "-t", "3000", "Title" };

    var parser = cli.ArgParser.init(allocator, &args);
    const config = try parser.parse();

    try testing.expectEqual(notification.Urgency.critical, config.urgency.?);
    try testing.expectEqual(@as(u32, 3000), config.timeout_ms.?);
}

test "Parse long options" {
    const allocator = testing.allocator;
    const args = [_][]const u8{ "znotify", "--urgency=low", "--timeout=1000", "Title" };

    var parser = cli.ArgParser.init(allocator, &args);
    const config = try parser.parse();

    try testing.expectEqual(notification.Urgency.low, config.urgency.?);
    try testing.expectEqual(@as(u32, 1000), config.timeout_ms.?);
}

test "Special commands" {
    const allocator = testing.allocator;

    {
        const args = [_][]const u8{ "znotify", "--help" };
        var parser = cli.ArgParser.init(allocator, &args);
        const config = try parser.parse();
        try testing.expect(config.help);
    }

    {
        const args = [_][]const u8{ "znotify", "--version" };
        var parser = cli.ArgParser.init(allocator, &args);
        const config = try parser.parse();
        try testing.expect(config.version);
    }
}

const validation = @import("utils/validation.zig");
const escaping = @import("utils/escaping.zig");

test "Validate title" {
    // Valid title
    _ = try validation.validateTitle("Valid Title");

    // Empty title should fail
    try testing.expectError(errors.ZNotifyError.MissingRequiredField, validation.validateTitle(""));

    // Too long title should fail
    const long_title = "a" ** 101;
    try testing.expectError(errors.ZNotifyError.TitleTooLong, validation.validateTitle(long_title));
}

test "XML escaping" {
    const allocator = testing.allocator;

    const input = "<test> & \"quotes\"";
    const escaped = try validation.escapeXml(allocator, input);
    defer allocator.free(escaped);

    try testing.expectEqualStrings("&lt;test&gt; &amp; &quot;quotes&quot;", escaped);
}

test "String truncation" {
    const allocator = testing.allocator;

    const text = "Hello World";
    const truncated = try validation.truncateString(allocator, text, 8);
    defer allocator.free(truncated);

    try testing.expectEqualStrings("Hello...", truncated);
}

test "UTF-8 validation" {
    try testing.expect(validation.isValidUtf8("Hello World"));
    try testing.expect(validation.isValidUtf8("Hello 世界"));
    try testing.expect(!validation.isValidUtf8(&[_]u8{ 0xFF, 0xFE, 0xFD }));
}

test "Shell escaping" {
    const allocator = testing.allocator;

    const input = "test; rm -rf /";
    const escaped = try escaping.escapeShell(allocator, input);
    defer allocator.free(escaped);

    try testing.expectEqualStrings("'test; rm -rf /'", escaped);
}

const backend = @import("platform/backend.zig");

test "Platform detection" {
    const platform = backend.Platform.detect();
    try testing.expect(platform != .unknown);
}

test "Terminal backend" {
    const allocator = testing.allocator;

    var term_backend = try backend.createTerminalBackend(allocator);
    defer term_backend.deinit();

    var notif = try notification.Notification.init(allocator, "Test", "Message");
    defer notif.deinit();

    const id = try term_backend.send(notif);
    try testing.expect(id > 0);

    try term_backend.close(id);
    try testing.expect(term_backend.isAvailable());

    const caps = try term_backend.getCapabilities(allocator);
    defer allocator.free(caps);
    try testing.expectEqualStrings("terminal", caps);
}

test "Platform backend creation" {
    const allocator = testing.allocator;

    // Should create appropriate backend or return error
    const platform_backend = backend.createPlatformBackend(allocator) catch |err| {
        try testing.expect(err == errors.ZNotifyError.PlatformNotSupported or
            err == errors.ZNotifyError.BackendInitFailed);
        return;
    };
    defer platform_backend.deinit();

    // If created, should be functional
    const caps = try platform_backend.getCapabilities(allocator);
    allocator.free(caps);
}

test "Linux backend D-Bus connection" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    const linux = @import("platform/linux.zig");

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
    const linux = @import("platform/linux.zig");

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

test "Windows backend COM initialization" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const windows = @import("platform/windows.zig");

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
    const windows = @import("platform/windows.zig");

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
    const windows = @import("platform/windows.zig");

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
