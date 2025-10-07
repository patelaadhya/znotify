const std = @import("std");
const notification = @import("../notification.zig");
const errors = @import("../errors.zig");
const backend = @import("backend.zig");

/// macOS notification backend using UserNotifications framework.
///
/// Planned implementation:
/// - macOS 10.14+: UserNotifications framework (UNUserNotificationCenter)
/// - macOS 10.12-10.13: NSUserNotificationCenter fallback
///
/// Features to support:
/// - Rich notifications with title, subtitle, body, and icons
/// - Action buttons and reply fields
/// - Notification categories and threading
/// - Sound, badge, and critical alerts
/// - Delivery scheduling and time-sensitive notifications
///
/// Currently a stub - returns PlatformNotSupported for all operations.
pub const MacOSBackend = struct {
    allocator: std.mem.Allocator,

    /// Initialize macOS backend (stub).
    pub fn init(allocator: std.mem.Allocator) !*MacOSBackend {
        const self = try allocator.create(MacOSBackend);
        self.* = MacOSBackend{ .allocator = allocator };
        return self;
    }

    /// Clean up macOS backend resources.
    pub fn deinit(self: *MacOSBackend) void {
        self.allocator.destroy(self);
    }

    /// Send notification via UserNotifications framework (stub).
    /// Returns PlatformNotSupported until implemented.
    pub fn send(_: *MacOSBackend, notif: notification.Notification) !u32 {
        _ = notif;
        return errors.ZNotifyError.PlatformNotSupported;
    }

    /// Close/dismiss notification (stub).
    /// Returns PlatformNotSupported until implemented.
    pub fn close(_: *MacOSBackend, _: u32) !void {
        return errors.ZNotifyError.PlatformNotSupported;
    }

    /// Get backend capabilities (stub).
    /// Caller owns returned memory.
    pub fn getCapabilities(_: *MacOSBackend, allocator: std.mem.Allocator) ![]const u8 {
        return allocator.dupe(u8, "none");
    }

    /// macOS backend is not yet implemented.
    pub fn isAvailable(_: *MacOSBackend) bool {
        return false;
    }

    /// VTable implementation for macOS backend.
    pub const vtable = backend.Backend.VTable{
        .init = @ptrCast(&MacOSBackend.init),
        .deinit = @ptrCast(&MacOSBackend.deinit),
        .send = @ptrCast(&MacOSBackend.send),
        .close = @ptrCast(&MacOSBackend.close),
        .getCapabilities = @ptrCast(&MacOSBackend.getCapabilities),
        .isAvailable = @ptrCast(&MacOSBackend.isAvailable),
    };
};

/// Create macOS notification backend (stub).
/// Returns a backend that reports as unavailable until implementation is complete.
pub fn createBackend(allocator: std.mem.Allocator) !backend.Backend {
    const macos_backend = try MacOSBackend.init(allocator);
    return backend.Backend{
        .ptr = macos_backend,
        .vtable = &MacOSBackend.vtable,
    };
}
