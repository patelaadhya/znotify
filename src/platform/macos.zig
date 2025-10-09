const std = @import("std");
const notification = @import("../notification.zig");
const errors = @import("../errors.zig");
const backend = @import("backend.zig");
const builtin = @import("builtin");

// Only import our Objective-C bindings on macOS
const objc = if (builtin.os.tag == .macos) @import("objc.zig") else struct {};

// Import UserNotifications framework headers on macOS
const c = if (builtin.os.tag == .macos) @cImport({
    @cInclude("UserNotifications/UserNotifications.h");
    @cInclude("Foundation/Foundation.h");
}) else struct {};

/// macOS notification backend using UserNotifications framework.
///
/// Implementation:
/// - Requires macOS 10.14+ (Mojave or later)
/// - Uses UNUserNotificationCenter for all notifications
/// - Must run from app bundle (not standalone binary)
///
/// Features:
/// - Rich notifications with title, subtitle, body, and icons
/// - Authorization request and status tracking
/// - Notification delivery via UserNotifications framework
pub const MacOSBackend = struct {
    allocator: std.mem.Allocator,
    /// Next notification ID to assign
    next_id: u32 = 1,
    /// Whether backend is available
    available: bool = false,
    /// Whether notification authorization was granted
    authorized: bool = false,

    /// Initialize macOS backend and determine API availability.
    pub fn init(allocator: std.mem.Allocator) !*MacOSBackend {
        const self = try allocator.create(MacOSBackend);
        self.* = MacOSBackend{
            .allocator = allocator,
            .next_id = 1,
            .available = false,
            .authorized = false,
        };

        // Only initialize on macOS
        if (builtin.os.tag != .macos) {
            return self;
        }

        // Detect macOS version - require 10.14+ (Mojave)
        const version = try detectMacOSVersion();
        if (version.major < 10 or (version.major == 10 and version.minor < 14)) {
            std.debug.print("ERROR: macOS 10.14+ (Mojave) required for notifications\n", .{});
            std.debug.print("Current version: {}.{}.{}\n", .{ version.major, version.minor, version.patch });
            return self;
        }

        // Initialize UserNotifications framework
        self.initModernAPI() catch |err| {
            std.debug.print("Failed to initialize UserNotifications: {}\n", .{err});
            return self;
        };

        self.available = true;
        return self;
    }

    /// Clean up macOS backend resources.
    pub fn deinit(self: *MacOSBackend) void {
        self.allocator.destroy(self);
    }

    /// macOS version structure
    const MacOSVersion = struct {
        major: i64,
        minor: i64,
        patch: i64,
    };

    /// Detect macOS version using NSProcessInfo
    pub fn detectMacOSVersion() !MacOSVersion {
        if (builtin.os.tag != .macos) {
            return MacOSVersion{ .major = 0, .minor = 0, .patch = 0 };
        }

        const NSProcessInfo = objc.getClass("NSProcessInfo") orelse return error.ClassNotFound;
        const info = NSProcessInfo.msgSend(objc.Object, "processInfo", .{});

        // Get operatingSystemVersion property
        // This returns an NSOperatingSystemVersion struct
        const version = info.getProperty(NSOperatingSystemVersion, "operatingSystemVersion");

        return MacOSVersion{
            .major = version.majorVersion,
            .minor = version.minorVersion,
            .patch = version.patchVersion,
        };
    }

    /// NSOperatingSystemVersion extern struct matching Cocoa headers
    const NSOperatingSystemVersion = extern struct {
        majorVersion: i64,
        minorVersion: i64,
        patchVersion: i64,
    };

    /// Initialize modern UserNotifications framework (macOS 10.14+)
    fn initModernAPI(self: *MacOSBackend) !void {
        // Verify the class exists
        const UNUserNotificationCenter = objc.getClass("UNUserNotificationCenter") orelse {
            return error.ClassNotFound;
        };
        _ = UNUserNotificationCenter;

        // CRITICAL: currentNotificationCenter requires running from an app bundle
        // Check if we're in a proper app bundle by verifying bundle identifier exists
        const NSBundle = objc.getClass("NSBundle") orelse return error.ClassNotFound;
        const mainBundle = NSBundle.msgSend(objc.Object, "mainBundle", .{});
        const bundleId = mainBundle.msgSend(objc.Object, "bundleIdentifier", .{});

        // If bundleIdentifier is nil, we're not running from an app bundle
        // Return error silently to allow fallback to legacy API
        if (bundleId.value == null) {
            return error.NotInAppBundle;
        }

        // Mark as authorized - actual authorization happens on first notification send
        self.authorized = true;
    }


    /// Send notification via UserNotifications framework
    pub fn send(self: *MacOSBackend, notif: notification.Notification) !u32 {
        if (!self.available or !self.authorized) {
            return errors.ZNotifyError.NotificationFailed;
        }

        try self.sendModern(notif);

        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    /// Send notification using modern UserNotifications API
    fn sendModern(self: *MacOSBackend, notif: notification.Notification) !void {
        // Get UNUserNotificationCenter
        const UNUserNotificationCenter = objc.getClass("UNUserNotificationCenter") orelse return error.ClassNotFound;
        const center = UNUserNotificationCenter.msgSend(objc.Object, "currentNotificationCenter", .{});

        // Check current authorization status first
        const SettingsHandlerFn = fn (block: *anyopaque, settings: *anyopaque) callconv(.c) void;
        const AuthStatus = struct {
            var status: i64 = 0; // 0 = notDetermined, 1 = denied, 2 = authorized, 3 = provisional, 4 = ephemeral
        };

        var settings_block = objc.makeBlock(SettingsHandlerFn, &struct {
            fn callback(_: *anyopaque, settings: *anyopaque) callconv(.c) void {
                const settings_obj = objc.Object{ .value = @ptrCast(@alignCast(settings)) };
                // authorizationStatus is a property returning UNAuthorizationStatus enum
                AuthStatus.status = settings_obj.getProperty(i64, "authorizationStatus");
            }
        }.callback);

        center.msgSend(void, "getNotificationSettingsWithCompletionHandler:", .{&settings_block});
        std.Thread.sleep(100 * std.time.ns_per_ms);

        // If not authorized, request authorization
        if (AuthStatus.status != 2) { // 2 = authorized
            std.debug.print("\n⚠️  Requesting notification permission. Please click 'Allow' when prompted.\n\n", .{});

            const options: i64 = (1 << 0) | (1 << 1) | (1 << 2);
            const CompletionHandlerFn = fn (block: *anyopaque, granted: u8, err: ?*anyopaque) callconv(.c) void;
            var completion_block = objc.makeBlock(CompletionHandlerFn, &struct {
                fn callback(_: *anyopaque, granted: u8, err: ?*anyopaque) callconv(.c) void {
                    AuthStatus.status = if (granted != 0) @as(i64, 2) else @as(i64, 1);
                    _ = err;
                }
            }.callback);

            center.msgSend(void, "requestAuthorizationWithOptions:completionHandler:", .{ options, &completion_block });

            // Wait for user to respond to authorization dialog
            std.Thread.sleep(3000 * std.time.ns_per_ms);
        }

        // Don't fail if authorization is denied - let the notification attempt proceed
        // macOS will handle showing authorization prompts if needed

        // Create notification content
        const UNMutableNotificationContent = objc.getClass("UNMutableNotificationContent") orelse return error.ClassNotFound;
        const content = UNMutableNotificationContent.msgSend(objc.Object, "alloc", .{});
        const initializedContent = content.msgSend(objc.Object, "init", .{});
        defer initializedContent.msgSend(void, "release", .{});

        // Create null-terminated copies of title and message
        var title_buf: [256:0]u8 = undefined;
        const title_z = try std.fmt.bufPrintZ(&title_buf, "{s}", .{notif.title});

        var message_buf: [1024:0]u8 = undefined;
        const message_z = try std.fmt.bufPrintZ(&message_buf, "{s}", .{notif.message});

        // Set title and body
        const NSString = objc.getClass("NSString") orelse return error.ClassNotFound;
        const titleStr = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{title_z.ptr});
        initializedContent.msgSend(void, "setTitle:", .{titleStr.value});

        const bodyStr = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{message_z.ptr});
        initializedContent.msgSend(void, "setBody:", .{bodyStr.value});

        // Create notification request with unique identifier
        const UNNotificationRequest = objc.getClass("UNNotificationRequest") orelse return error.ClassNotFound;

        var id_buf: [64:0]u8 = undefined;
        const id_str = try std.fmt.bufPrintZ(&id_buf, "znotify-{d}", .{self.next_id});
        const identifierStr = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{id_str.ptr});

        const request = UNNotificationRequest.msgSend(
            objc.Object,
            "requestWithIdentifier:content:trigger:",
            .{ identifierStr.value, initializedContent.value, @as(?*anyopaque, null) },
        );

        // Add notification request to center
        center.msgSend(void, "addNotificationRequest:withCompletionHandler:", .{ request.value, @as(?*anyopaque, null) });
    }


    /// Close/dismiss notification by ID
    pub fn close(_: *MacOSBackend, _: u32) !void {
        // macOS doesn't provide a direct API to dismiss notifications by our internal ID
        // Notifications auto-dismiss based on system settings
    }

    /// Get backend capabilities
    pub fn getCapabilities(_: *MacOSBackend, allocator: std.mem.Allocator) ![]const u8 {
        return allocator.dupe(u8, "body,actions,images,sounds,badge");
    }

    /// Check if macOS backend is available
    pub fn isAvailable(self: *MacOSBackend) bool {
        return self.available and self.authorized;
    }

    /// VTable implementation for macOS backend
    pub const vtable = backend.Backend.VTable{
        .init = @ptrCast(&MacOSBackend.init),
        .deinit = @ptrCast(&MacOSBackend.deinit),
        .send = @ptrCast(&MacOSBackend.send),
        .close = @ptrCast(&MacOSBackend.close),
        .getCapabilities = @ptrCast(&MacOSBackend.getCapabilities),
        .isAvailable = @ptrCast(&MacOSBackend.isAvailable),
    };
};

/// Create macOS notification backend
pub fn createBackend(allocator: std.mem.Allocator) !backend.Backend {
    const macos_backend = try MacOSBackend.init(allocator);
    return backend.Backend{
        .ptr = macos_backend,
        .vtable = &MacOSBackend.vtable,
    };
}
