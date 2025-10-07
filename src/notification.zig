const std = @import("std");

/// Notification urgency levels that determine how the notification is displayed.
/// Maps to platform-specific urgency/priority mechanisms.
pub const Urgency = enum(u8) {
    /// Low priority notification - minimal interruption
    low = 0,
    /// Normal priority notification - default behavior
    normal = 1,
    /// Critical priority notification - demands immediate attention
    critical = 2,

    /// Converts a string to an Urgency enum value.
    /// Returns error.InvalidUrgency if the string is not recognized.
    pub fn fromString(str: []const u8) !Urgency {
        if (std.mem.eql(u8, str, "low")) return .low;
        if (std.mem.eql(u8, str, "normal")) return .normal;
        if (std.mem.eql(u8, str, "critical")) return .critical;
        return error.InvalidUrgency;
    }

    /// Converts an Urgency enum value to its string representation.
    pub fn toString(self: Urgency) []const u8 {
        return switch (self) {
            .low => "low",
            .normal => "normal",
            .critical => "critical",
        };
    }
};

/// Built-in icon types that map to platform-specific system icons.
/// These ensure consistent appearance across different operating systems.
pub const BuiltinIcon = enum {
    /// Information icon - general notification
    info,
    /// Warning icon - potential issue
    warning,
    /// Error icon - something went wrong
    @"error",
    /// Question icon - user input needed
    question,
    /// Success icon - operation completed successfully
    success,

    /// Converts a string to a BuiltinIcon enum value.
    /// Returns error.InvalidIcon if the string is not recognized.
    pub fn fromString(str: []const u8) !BuiltinIcon {
        if (std.mem.eql(u8, str, "info")) return .info;
        if (std.mem.eql(u8, str, "warning")) return .warning;
        if (std.mem.eql(u8, str, "error")) return .@"error";
        if (std.mem.eql(u8, str, "question")) return .question;
        if (std.mem.eql(u8, str, "success")) return .success;
        return error.InvalidIcon;
    }
};

/// Icon representation supporting multiple sources.
/// Manages memory for dynamically allocated icon paths and URLs.
pub const Icon = union(enum) {
    /// No icon displayed
    none,
    /// Built-in system icon
    builtin: BuiltinIcon,
    /// Path to an icon file on the filesystem
    file_path: []const u8,
    /// URL to a remote icon image
    url: []const u8,

    /// Frees any allocated memory used by this icon.
    /// Safe to call multiple times. Only frees memory for file_path and url variants.
    pub fn deinit(self: *Icon, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .file_path => |path| allocator.free(path),
            .url => |url| allocator.free(url),
            else => {},
        }
    }
};

/// Reason why a notification was closed.
/// Used for tracking notification lifecycle events.
pub const CloseReason = enum {
    /// Notification timeout expired
    expired,
    /// User dismissed the notification
    dismissed,
    /// Application closed the notification programmatically
    closed_by_app,
    /// Close reason is unknown or not specified
    undefined,
};

/// Main notification structure containing all data needed to display a notification.
/// Manages memory for all dynamic fields and provides a safe lifecycle with init/deinit.
pub const Notification = struct {
    // Required fields
    /// Notification title (duplicated on heap)
    title: []const u8,
    /// Notification body message (duplicated on heap)
    message: []const u8,

    // Optional fields with defaults
    /// Priority level affecting display behavior
    urgency: Urgency = .normal,
    /// Display timeout in milliseconds (null = persistent)
    timeout_ms: ?u32 = 5000,
    /// Icon to display with the notification
    icon: Icon = .none,
    /// Optional category for grouping notifications
    category: ?[]const u8 = null,
    /// Application name shown as notification source
    app_name: []const u8 = "znotify",
    /// ID of notification to replace (for updates)
    replace_id: ?u32 = null,

    // Platform-specific hints (simplified for now)
    /// Whether to play a sound when showing the notification
    sound_enabled: bool = true,

    // Allocator for dynamic fields
    /// Allocator used for all memory management
    allocator: std.mem.Allocator,

    /// Creates a new notification with the given title and message.
    /// Duplicates strings on the heap using the provided allocator.
    /// Caller must call deinit() to free allocated memory.
    pub fn init(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !Notification {
        return Notification{
            .allocator = allocator,
            .title = try allocator.dupe(u8, title),
            .message = try allocator.dupe(u8, message),
        };
    }

    /// Frees all memory allocated by this notification.
    /// Safe to call even if some fields were never set.
    /// Uses pointer comparison to avoid freeing the default app_name string literal.
    pub fn deinit(self: *Notification) void {
        self.allocator.free(self.title);
        self.allocator.free(self.message);
        if (self.category) |cat| {
            self.allocator.free(cat);
        }
        if (self.app_name.ptr != "znotify".ptr) {
            self.allocator.free(self.app_name);
        }
        self.icon.deinit(self.allocator);
    }

    /// Sets the urgency level for this notification.
    pub fn setUrgency(self: *Notification, urgency: Urgency) void {
        self.urgency = urgency;
    }

    /// Sets the display timeout in milliseconds.
    /// Pass null for a persistent notification that doesn't auto-dismiss.
    pub fn setTimeout(self: *Notification, timeout_ms: ?u32) void {
        self.timeout_ms = timeout_ms;
    }

    /// Sets the icon for this notification.
    /// Frees any previously set icon and duplicates the new icon data if needed.
    pub fn setIcon(self: *Notification, icon: Icon) !void {
        self.icon.deinit(self.allocator);
        self.icon = switch (icon) {
            .none, .builtin => icon,
            .file_path => |path| .{ .file_path = try self.allocator.dupe(u8, path) },
            .url => |url| .{ .url = try self.allocator.dupe(u8, url) },
        };
    }

    /// Sets the category for grouping related notifications.
    /// Frees any previously set category and duplicates the new one.
    pub fn setCategory(self: *Notification, category: []const u8) !void {
        if (self.category) |cat| {
            self.allocator.free(cat);
        }
        self.category = try self.allocator.dupe(u8, category);
    }

    /// Sets the application name shown as the notification source.
    /// Frees any previously set app name and duplicates the new one.
    pub fn setAppName(self: *Notification, app_name: []const u8) !void {
        if (self.app_name.ptr != "znotify".ptr) {
            self.allocator.free(self.app_name);
        }
        self.app_name = try self.allocator.dupe(u8, app_name);
    }
};

/// Fluent API builder for constructing notifications with method chaining.
/// Provides an ergonomic interface for setting optional notification properties.
///
/// Example:
///     var builder = try NotificationBuilder.init(allocator, "Title", "Message");
///     var notif = builder.urgency(.critical).timeout(10000).build();
///     defer notif.deinit();
pub const NotificationBuilder = struct {
    /// The notification being constructed
    notification: Notification,

    /// Creates a new notification builder with the required title and message.
    /// Returns a builder that can be used to set optional properties via method chaining.
    pub fn init(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !NotificationBuilder {
        return NotificationBuilder{
            .notification = try Notification.init(allocator, title, message),
        };
    }

    /// Sets the urgency level. Returns self for method chaining.
    pub fn urgency(self: *NotificationBuilder, value: Urgency) *NotificationBuilder {
        self.notification.urgency = value;
        return self;
    }

    /// Sets the timeout in milliseconds. Pass null for persistent. Returns self for method chaining.
    pub fn timeout(self: *NotificationBuilder, ms: ?u32) *NotificationBuilder {
        self.notification.timeout_ms = ms;
        return self;
    }

    /// Sets the icon. Returns self for method chaining.
    /// May return an error if icon allocation fails.
    pub fn icon(self: *NotificationBuilder, value: Icon) !*NotificationBuilder {
        try self.notification.setIcon(value);
        return self;
    }

    /// Sets the category. Returns self for method chaining.
    /// May return an error if category allocation fails.
    pub fn category(self: *NotificationBuilder, value: []const u8) !*NotificationBuilder {
        try self.notification.setCategory(value);
        return self;
    }

    /// Consumes the builder and returns the constructed notification.
    /// Caller is responsible for calling deinit() on the returned notification.
    pub fn build(self: NotificationBuilder) Notification {
        return self.notification;
    }
};
