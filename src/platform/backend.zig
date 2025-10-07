const std = @import("std");
const notification = @import("../notification.zig");
const errors = @import("../errors.zig");

/// Platform backend interface
pub const Backend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        init: *const fn (allocator: std.mem.Allocator) anyerror!*anyopaque,
        deinit: *const fn (self: *anyopaque) void,
        send: *const fn (self: *anyopaque, notif: notification.Notification) anyerror!u32,
        close: *const fn (self: *anyopaque, id: u32) anyerror!void,
        getCapabilities: *const fn (self: *anyopaque, allocator: std.mem.Allocator) anyerror![]const u8,
        isAvailable: *const fn (self: *anyopaque) bool,
    };

    pub fn init(self: Backend) !void {
        // Backend-specific initialization
        _ = self;
    }

    pub fn deinit(self: Backend) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn send(self: Backend, notif: notification.Notification) !u32 {
        return self.vtable.send(self.ptr, notif);
    }

    pub fn close(self: Backend, id: u32) !void {
        return self.vtable.close(self.ptr, id);
    }

    pub fn getCapabilities(self: Backend, allocator: std.mem.Allocator) ![]const u8 {
        return self.vtable.getCapabilities(self.ptr, allocator);
    }

    pub fn isAvailable(self: Backend) bool {
        return self.vtable.isAvailable(self.ptr);
    }
};

/// Platform detection
pub const Platform = enum {
    windows,
    linux,
    macos,
    freebsd,
    unknown,

    pub fn detect() Platform {
        return switch (@import("builtin").os.tag) {
            .windows => .windows,
            .linux => .linux,
            .macos => .macos,
            .freebsd => .freebsd,
            else => .unknown,
        };
    }

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

/// Get the appropriate backend for the current platform
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

// Platform-specific backend creation (forward declarations)
fn createWindowsBackend(allocator: std.mem.Allocator) !Backend {
    if (@import("builtin").os.tag != .windows) {
        return errors.ZNotifyError.PlatformNotSupported;
    }
    const windows = @import("windows.zig");
    return windows.createBackend(allocator);
}

fn createLinuxBackend(allocator: std.mem.Allocator) !Backend {
    if (@import("builtin").os.tag != .linux and @import("builtin").os.tag != .freebsd) {
        return errors.ZNotifyError.PlatformNotSupported;
    }
    const linux = @import("linux.zig");
    return linux.createBackend(allocator);
}

fn createMacOSBackend(allocator: std.mem.Allocator) !Backend {
    if (@import("builtin").os.tag != .macos) {
        return errors.ZNotifyError.PlatformNotSupported;
    }
    const macos = @import("macos.zig");
    return macos.createBackend(allocator);
}

/// Fallback terminal backend for testing
pub const TerminalBackend = struct {
    allocator: std.mem.Allocator,
    next_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) !*TerminalBackend {
        const self = try allocator.create(TerminalBackend);
        self.* = TerminalBackend{ .allocator = allocator };
        return self;
    }

    pub fn deinit(self: *TerminalBackend) void {
        self.allocator.destroy(self);
    }

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

    pub fn close(_: *TerminalBackend, id: u32) !void {
        const stderr_file = std.fs.File.stderr();
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "[Notification {} closed]\n", .{id}) catch return error.BufferTooSmall;
        _ = stderr_file.write(msg) catch {};
    }

    pub fn getCapabilities(_: *TerminalBackend, allocator: std.mem.Allocator) ![]const u8 {
        return allocator.dupe(u8, "terminal");
    }

    pub fn isAvailable(_: *TerminalBackend) bool {
        return true;
    }

    pub const vtable = Backend.VTable{
        .init = @ptrCast(&TerminalBackend.init),
        .deinit = @ptrCast(&TerminalBackend.deinit),
        .send = @ptrCast(&TerminalBackend.send),
        .close = @ptrCast(&TerminalBackend.close),
        .getCapabilities = @ptrCast(&TerminalBackend.getCapabilities),
        .isAvailable = @ptrCast(&TerminalBackend.isAvailable),
    };
};

/// Create a terminal backend for testing
pub fn createTerminalBackend(allocator: std.mem.Allocator) !Backend {
    const terminal = try TerminalBackend.init(allocator);
    return Backend{
        .ptr = terminal,
        .vtable = &TerminalBackend.vtable,
    };
}
