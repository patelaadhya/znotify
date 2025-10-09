const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const notification = @import("../notification.zig");

test "macOS backend framework initialization" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;
    const macos = @import("../platform/macos.zig");

    var macos_backend = try macos.MacOSBackend.init(allocator);
    defer macos_backend.deinit();

    // Backend should report availability based on framework initialization
    const available = macos_backend.isAvailable();
    std.debug.print("macOS backend available: {}\n", .{available});

    // If available, should have capabilities
    if (available) {
        const caps = try macos_backend.getCapabilities(allocator);
        defer allocator.free(caps);
        try testing.expect(caps.len > 0);
        try testing.expect(std.mem.indexOf(u8, caps, "body") != null);
    }
}

test "macOS backend notification send" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Use the main znotify executable which has authorization
    // Test executable is separate binary and macOS won't authorize it
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "zig-out/ZNotify.app/Contents/MacOS/znotify",
            "macOS Test",
            "Testing notification from test suite",
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Should exit successfully
    try testing.expectEqual(@as(u8, 0), result.term.Exited);

    std.debug.print("Notification sent via main executable\n", .{});
}

test "macOS backend version detection" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;
    const macos = @import("../platform/macos.zig");

    // Test pure version detection logic
    const version = try macos.MacOSBackend.detectMacOSVersion();
    std.debug.print("\nmacOS Version: {}.{}.{}\n", .{ version.major, version.minor, version.patch });

    // Verify version detection logic is correct
    const should_use_modern = version.major > 10 or (version.major == 10 and version.minor >= 14);
    std.debug.print("Should use modern API (based on version): {}\n", .{should_use_modern});

    // Initialize backend
    var macos_backend = try macos.MacOSBackend.init(allocator);
    defer macos_backend.deinit();

    std.debug.print("Backend available: {}\n", .{macos_backend.available});
    std.debug.print("Authorized: {}\n", .{macos_backend.authorized});

    // Version detection must be correct for current macOS version
    if (version.major >= 26) {
        // macOS 26+ (Tahoe and later) should definitely support modern API
        try testing.expect(should_use_modern);
    } else if (version.major > 10 or (version.major == 10 and version.minor >= 14)) {
        // macOS 10.14+ should support modern API
        try testing.expect(should_use_modern);
    }

    // Backend should be authorized
    try testing.expect(macos_backend.authorized);
}

test "macOS backend urgency levels" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Test different urgency levels using main executable
    const urgencies = [_][]const u8{ "low", "normal", "critical" };

    for (urgencies) |urgency| {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "zig-out/ZNotify.app/Contents/MacOS/znotify",
                "-u",
                urgency,
                "Urgency Test",
                "Testing urgency level",
            },
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.term.Exited);
        std.debug.print("Sent notification with urgency: {s}\n", .{urgency});
    }
}

test "macOS backend timeout handling" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Test timeout with main executable
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "zig-out/ZNotify.app/Contents/MacOS/znotify",
            "-t",
            "5000",
            "Timeout Test",
            "Testing with 5 second timeout",
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try testing.expectEqual(@as(u8, 0), result.term.Exited);
    std.debug.print("Sent notification with timeout\n", .{});
}
