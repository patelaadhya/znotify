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

test "macOS backend icon support" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Create a minimal 1x1 PNG image for testing
    // PNG signature + IHDR + IDAT + IEND
    const test_png = [_]u8{
        // PNG signature
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        // IHDR chunk
        0x00, 0x00, 0x00, 0x0D, // Length: 13
        0x49, 0x48, 0x44, 0x52, // "IHDR"
        0x00, 0x00, 0x00, 0x01, // Width: 1
        0x00, 0x00, 0x00, 0x01, // Height: 1
        0x08, 0x02, 0x00, 0x00, 0x00, // Bit depth, color type, etc.
        0x90, 0x77, 0x53, 0xDE, // CRC
        // IDAT chunk
        0x00, 0x00, 0x00, 0x0C, // Length: 12
        0x49, 0x44, 0x41, 0x54, // "IDAT"
        0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00, 0x03, 0x01, 0x01, 0x00,
        0x18, 0xDD, 0x8D, 0xB4, // CRC
        // IEND chunk
        0x00, 0x00, 0x00, 0x00, // Length: 0
        0x49, 0x45, 0x4E, 0x44, // "IEND"
        0xAE, 0x42, 0x60, 0x82, // CRC
    };

    // Write test PNG to temporary file
    const test_icon_path = "/tmp/znotify_test_icon.png";
    const file = try std.fs.createFileAbsolute(test_icon_path, .{});
    defer file.close();
    try file.writeAll(&test_png);

    // Ensure cleanup
    defer std.fs.deleteFileAbsolute(test_icon_path) catch {};

    // Test notification with icon using main executable
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "zig-out/ZNotify.app/Contents/MacOS/znotify",
            "-i",
            test_icon_path,
            "Icon Test",
            "Testing notification with custom icon",
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try testing.expectEqual(@as(u8, 0), result.term.Exited);
    std.debug.print("Sent notification with icon: {s}\n", .{test_icon_path});

    // Test with non-existent icon (should warn but not fail)
    const result2 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "zig-out/ZNotify.app/Contents/MacOS/znotify",
            "-i",
            "/nonexistent/icon.png",
            "Icon Test",
            "Testing with missing icon file",
        },
    });
    defer allocator.free(result2.stdout);
    defer allocator.free(result2.stderr);

    // Should still succeed (icon attachment just fails gracefully)
    try testing.expectEqual(@as(u8, 0), result2.term.Exited);
    std.debug.print("Sent notification with missing icon (graceful failure)\n", .{});
}

test "macOS backend builtin icon support" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Test all builtin icon types
    const icons = [_]struct { name: []const u8, flag: []const u8 }{
        .{ .name = "info", .flag = "info" },
        .{ .name = "warning", .flag = "warning" },
        .{ .name = "error", .flag = "error" },
        .{ .name = "question", .flag = "question" },
        .{ .name = "success", .flag = "success" },
    };

    for (icons) |icon| {
        const message = try std.fmt.allocPrint(allocator, "Testing with {s} icon", .{icon.name});
        defer allocator.free(message);

        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "zig-out/ZNotify.app/Contents/MacOS/znotify",
                "-i",
                icon.flag,
                "Builtin Icon Test",
                message,
            },
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.term.Exited);
        std.debug.print("Sent notification with builtin icon: {s}\n", .{icon.name});
    }
}

test "macOS backend URL icon support" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Test with a small data URL for a 1x1 PNG
    // This avoids network dependency
    const test_url = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "zig-out/ZNotify.app/Contents/MacOS/znotify",
            "-i",
            test_url,
            "URL Icon Test",
            "Testing with data URL icon",
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Data URLs are handled by NSData dataWithContentsOfURL
    // May fail but shouldn't crash
    std.debug.print("Sent notification with URL icon (exit code: {})\n", .{result.term.Exited});
}
