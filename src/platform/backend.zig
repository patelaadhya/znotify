const std = @import("std");
const notification = @import("../notification.zig");
const errors = @import("../errors.zig");

/// Platform-agnostic notification backend interface.
///
/// This provides a unified interface for sending notifications across different
/// operating systems using a vtable pattern for runtime polymorphism.
///
/// Each platform implements its own backend that conforms to this interface:
/// - Linux: D-Bus protocol via org.freedesktop.Notifications
/// - Windows: WinRT Toast API (future implementation)
/// - macOS: UserNotifications framework (future implementation)
pub const Backend = struct {
    /// Opaque pointer to the platform-specific backend implementation
    ptr: *anyopaque,
    /// Virtual function table for platform-specific operations
    vtable: *const VTable,

    /// Virtual function table defining the backend interface.
    /// All platform-specific backends must implement these functions.
    pub const VTable = struct {
        /// Initialize a new backend instance
        init: *const fn (allocator: std.mem.Allocator) anyerror!*anyopaque,
        /// Clean up backend resources
        deinit: *const fn (self: *anyopaque) void,
        /// Send a notification and return its ID
        send: *const fn (self: *anyopaque, notif: notification.Notification) anyerror!u32,
        /// Close/dismiss a notification by ID
        close: *const fn (self: *anyopaque, id: u32) anyerror!void,
        /// Get comma-separated list of backend capabilities
        getCapabilities: *const fn (self: *anyopaque, allocator: std.mem.Allocator) anyerror![]const u8,
        /// Check if the backend is available on this system
        isAvailable: *const fn (self: *anyopaque) bool,
    };

    /// Initialize the backend (reserved for future use).
    /// Currently backends are initialized during creation.
    pub fn init(self: Backend) !void {
        _ = self;
    }

    /// Clean up backend resources and free memory.
    /// Must be called when the backend is no longer needed.
    pub fn deinit(self: Backend) void {
        self.vtable.deinit(self.ptr);
    }

    /// Send a notification through the platform backend.
    /// Returns a unique notification ID that can be used to close it later.
    pub fn send(self: Backend, notif: notification.Notification) !u32 {
        return self.vtable.send(self.ptr, notif);
    }

    /// Close/dismiss an active notification by its ID.
    /// The ID should be one returned from a previous send() call.
    pub fn close(self: Backend, id: u32) !void {
        return self.vtable.close(self.ptr, id);
    }

    /// Get a comma-separated string of backend capabilities.
    /// Caller owns the returned memory and must free it.
    /// Common capabilities: "body", "actions", "icon", "sound", "persistence"
    pub fn getCapabilities(self: Backend, allocator: std.mem.Allocator) ![]const u8 {
        return self.vtable.getCapabilities(self.ptr, allocator);
    }

    /// Check if this backend is available on the current system.
    /// Returns true if the backend can send notifications.
    pub fn isAvailable(self: Backend) bool {
        return self.vtable.isAvailable(self.ptr);
    }
};

/// Supported operating system platforms.
/// Used for compile-time and runtime platform detection.
pub const Platform = enum {
    windows,
    linux,
    macos,
    freebsd,
    unknown,

    /// Detect the current platform at compile time.
    /// Returns the platform this binary was compiled for.
    pub fn detect() Platform {
        return switch (@import("builtin").os.tag) {
            .windows => .windows,
            .linux => .linux,
            .macos => .macos,
            .freebsd => .freebsd,
            else => .unknown,
        };
    }

    /// Convert platform enum to human-readable string.
    pub fn toString(self: Platform) []const u8 {
        return switch (self) {
            .windows => "Windows",
            .linux => "Linux",
            .macos => "macOS",
            .freebsd => "FreeBSD",
            .unknown => "Unknown",
        };
    }
};

/// Create the appropriate notification backend for the current platform.
/// Automatically detects the platform and instantiates the correct backend.
///
/// Returns:
/// - Windows: WindowsBackend (WinRT Toast API stub)
/// - Linux: LinuxBackend (D-Bus notifications via org.freedesktop.Notifications)
/// - macOS: MacOSBackend (UserNotifications framework stub)
/// - FreeBSD: LinuxBackend (Linux compatibility layer)
/// - Unknown: PlatformNotSupported error
pub fn createPlatformBackend(allocator: std.mem.Allocator) !Backend {
    const platform = Platform.detect();

    return switch (platform) {
        .windows => try createWindowsBackend(allocator),
        .linux => try createLinuxBackend(allocator),
        .macos => try createMacOSBackend(allocator),
        .freebsd => try createLinuxBackend(allocator), // Use Linux compatibility
        .unknown => errors.ZNotifyError.PlatformNotSupported,
    };
}

/// Create Windows-specific notification backend.
/// Returns PlatformNotSupported if not compiled for Windows.
fn createWindowsBackend(allocator: std.mem.Allocator) !Backend {
    if (@import("builtin").os.tag != .windows) {
        return errors.ZNotifyError.PlatformNotSupported;
    }
    const windows = @import("windows.zig");
    return windows.createBackend(allocator);
}

/// Create Linux-specific notification backend using D-Bus.
/// Returns PlatformNotSupported if not compiled for Linux or FreeBSD.
fn createLinuxBackend(allocator: std.mem.Allocator) !Backend {
    if (@import("builtin").os.tag != .linux and @import("builtin").os.tag != .freebsd) {
        return errors.ZNotifyError.PlatformNotSupported;
    }
    const linux = @import("linux.zig");
    return linux.createBackend(allocator);
}

/// Create macOS-specific notification backend.
/// Returns PlatformNotSupported if not compiled for macOS.
fn createMacOSBackend(allocator: std.mem.Allocator) !Backend {
    if (@import("builtin").os.tag != .macos) {
        return errors.ZNotifyError.PlatformNotSupported;
    }
    const macos = @import("macos.zig");
    return macos.createBackend(allocator);
}

/// Fallback terminal backend for testing and development.
/// Displays notifications as formatted text to stderr using ANSI colors.
/// Always available on any platform with a terminal.
pub const TerminalBackend = struct {
    allocator: std.mem.Allocator,
    /// Auto-incrementing notification ID counter
    next_id: u32 = 1,

    /// Initialize a new terminal backend instance.
    pub fn init(allocator: std.mem.Allocator) !*TerminalBackend {
        const self = try allocator.create(TerminalBackend);
        self.* = TerminalBackend{ .allocator = allocator };
        return self;
    }

    /// Clean up terminal backend resources.
    pub fn deinit(self: *TerminalBackend) void {
        self.allocator.destroy(self);
    }

    /// Display notification to terminal stderr with ANSI color formatting.
    /// Returns auto-generated notification ID.
    pub fn send(self: *TerminalBackend, notif: notification.Notification) !u32 {
        const stderr_file = std.fs.File.stderr();

        // ANSI color codes
        const color = switch (notif.urgency) {
            .low => "\x1b[34m",      // Blue
            .normal => "\x1b[37m",    // White
            .critical => "\x1b[31m",  // Red
        };
        const reset = "\x1b[0m";
        const bold = "\x1b[1m";

        // Format and write output
        var buf: [1024]u8 = undefined;
        var msg = std.fmt.bufPrint(&buf, "\n{s}{s}=== NOTIFICATION ==={s}\n", .{ bold, color, reset }) catch return error.BufferTooSmall;
        _ = stderr_file.write(msg) catch {};

        msg = std.fmt.bufPrint(&buf, "{s}Title:{s} {s}\n", .{ bold, reset, notif.title }) catch return error.BufferTooSmall;
        _ = stderr_file.write(msg) catch {};

        if (notif.message.len > 0) {
            msg = std.fmt.bufPrint(&buf, "{s}Message:{s} {s}\n", .{ bold, reset, notif.message }) catch return error.BufferTooSmall;
            _ = stderr_file.write(msg) catch {};
        }

        msg = std.fmt.bufPrint(&buf, "{s}Urgency:{s} {s}\n", .{ bold, reset, notif.urgency.toString() }) catch return error.BufferTooSmall;
        _ = stderr_file.write(msg) catch {};

        if (notif.timeout_ms) |timeout| {
            msg = std.fmt.bufPrint(&buf, "{s}Timeout:{s} {}ms\n", .{ bold, reset, timeout }) catch return error.BufferTooSmall;
            _ = stderr_file.write(msg) catch {};
        }

        msg = std.fmt.bufPrint(&buf, "{s}==================={s}\n\n", .{ color, reset }) catch return error.BufferTooSmall;
        _ = stderr_file.write(msg) catch {};

        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    /// Display notification close message to terminal.
    pub fn close(_: *TerminalBackend, id: u32) !void {
        const stderr_file = std.fs.File.stderr();
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "[Notification {} closed]\n", .{id}) catch return error.BufferTooSmall;
        _ = stderr_file.write(msg) catch {};
    }

    /// Return terminal backend capabilities.
    /// Caller owns returned memory.
    pub fn getCapabilities(_: *TerminalBackend, allocator: std.mem.Allocator) ![]const u8 {
        return allocator.dupe(u8, "terminal");
    }

    /// Terminal backend is always available.
    pub fn isAvailable(_: *TerminalBackend) bool {
        return true;
    }

    /// VTable implementation for terminal backend.
    pub const vtable = Backend.VTable{
        .init = @ptrCast(&TerminalBackend.init),
        .deinit = @ptrCast(&TerminalBackend.deinit),
        .send = @ptrCast(&TerminalBackend.send),
        .close = @ptrCast(&TerminalBackend.close),
        .getCapabilities = @ptrCast(&TerminalBackend.getCapabilities),
        .isAvailable = @ptrCast(&TerminalBackend.isAvailable),
    };
};

/// Create a terminal backend for testing and development.
/// This backend displays notifications to stderr and is always available.
pub fn createTerminalBackend(allocator: std.mem.Allocator) !Backend {
    const terminal = try TerminalBackend.init(allocator);
    return Backend{
        .ptr = terminal,
        .vtable = &TerminalBackend.vtable,
    };
}
