const std = @import("std");
const backend = @import("platform/backend.zig");
const notification = @import("notification.zig");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse CLI arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = cli.ArgParser.init(allocator, args);
    var config = parser.parse() catch |err| {
        if (err == error.HelpRequested or err == error.VersionRequested) {
            return;
        }
        std.debug.print("Error parsing arguments: {}\n", .{err});
        try cli.printHelp();
        return err;
    };
    defer config.deinit();

    // Handle special commands first (before validating required arguments)
    if (config.help) {
        try cli.printHelp();
        return;
    }

    if (config.version) {
        try cli.printVersion();
        return;
    }

    if (config.doctor) {
        std.debug.print("Doctor command not yet implemented\n", .{});
        return;
    }

    if (config.init_config) {
        std.debug.print("Init-config command not yet implemented\n", .{});
        return;
    }

    // Validate that we have required arguments (title)
    if (config.title == null or config.title.?.len == 0) {
        std.debug.print("Error: Title is required\n", .{});
        try cli.printHelp();
        return error.InvalidArguments;
    }

    // Try to create platform-specific backend
    var platform_backend = backend.createPlatformBackend(allocator) catch |err| {
        std.debug.print("Platform backend failed: {}, using terminal\n", .{err});
        var term = try backend.createTerminalBackend(allocator);
        defer term.deinit();

        var notif = try notification.Notification.init(allocator, config.title.?, config.message orelse "");
        defer notif.deinit();

        // Apply config settings
        if (config.urgency) |u| notif.urgency = u;
        if (config.timeout_ms) |t| notif.timeout_ms = t;
        if (config.duration) |d| notif.windows_duration = d;
        if (config.app_name) |a| notif.app_name = a;
        if (config.replace_id) |r| notif.replace_id = r;
        if (config.icon) |i| {
            // Try to parse as builtin icon first
            if (notification.BuiltinIcon.fromString(i)) |builtin| {
                notif.icon = .{ .builtin = builtin };
            } else |_| {
                // Check if it's a URL (http://, https://, or file://)
                if (std.mem.startsWith(u8, i, "http://") or
                    std.mem.startsWith(u8, i, "https://") or
                    std.mem.startsWith(u8, i, "data:") or
                    std.mem.startsWith(u8, i, "file://")) {
                    const url = try allocator.dupe(u8, i);
                    notif.icon = .{ .url = url };
                } else {
                    // Treat as file path
                    const icon_path = try allocator.dupe(u8, i);
                    notif.icon = .{ .file_path = icon_path };
                }
            }
        }

        // Apply actions if any
        if (config.actions.items.len > 0) {
            const actions = try allocator.alloc(notification.Action, config.actions.items.len);
            for (config.actions.items, 0..) |action_config, i| {
                actions[i] = .{
                    .id = try allocator.dupe(u8, action_config.id),
                    .label = try allocator.dupe(u8, action_config.label),
                };
            }
            notif.actions = actions;
        }

        const id = try term.send(notif);
        std.debug.print("Notification sent with ID: {}\n", .{id});
        return;
    };
    defer platform_backend.deinit();

    var notif = try notification.Notification.init(allocator, config.title.?, config.message orelse "");
    defer notif.deinit();

    // Apply config settings
    if (config.urgency) |u| notif.urgency = u;
    if (config.timeout_ms) |t| notif.timeout_ms = t;
    if (config.duration) |d| notif.windows_duration = d;
    if (config.app_name) |a| notif.app_name = a;
    if (config.replace_id) |r| notif.replace_id = r;
    if (config.icon) |i| {
        // Try to parse as builtin icon first
        if (notification.BuiltinIcon.fromString(i)) |builtin| {
            notif.icon = .{ .builtin = builtin };
        } else |_| {
            // Check if it's a URL (http://, https://, or file://)
            if (std.mem.startsWith(u8, i, "http://") or
                std.mem.startsWith(u8, i, "https://") or
                std.mem.startsWith(u8, i, "data:") or
                std.mem.startsWith(u8, i, "file://")) {
                const url = try allocator.dupe(u8, i);
                notif.icon = .{ .url = url };
            } else {
                // Treat as file path
                const icon_path = try allocator.dupe(u8, i);
                notif.icon = .{ .file_path = icon_path };
            }
        }
    }

    // Apply actions if any
    if (config.actions.items.len > 0) {
        const actions = try allocator.alloc(notification.Action, config.actions.items.len);
        for (config.actions.items, 0..) |action_config, i| {
            actions[i] = .{
                .id = try allocator.dupe(u8, action_config.id),
                .label = try allocator.dupe(u8, action_config.label),
            };
        }
        notif.actions = actions;
    }

    const id = try platform_backend.send(notif);
    std.debug.print("Notification sent with ID: {}\n", .{id});

    // On macOS, run event loop briefly to allow async notification dispatch
    const builtin_os = @import("builtin");
    if (builtin_os.os.tag == .macos) {
        const c = @cImport({
            @cInclude("CoreFoundation/CoreFoundation.h");
        });
        // Brief run loop to dispatch the notification before exiting
        _ = c.CFRunLoopRunInMode(c.kCFRunLoopDefaultMode, 0.2, 0);
    }

    // If wait mode is enabled and we have actions, subscribe and wait for signal
    if (config.wait and config.actions.items.len > 0) {
        const builtin = @import("builtin");
        if (builtin.os.tag == .linux) {
            const linux = @import("platform/linux.zig");

            // Use the same backend connection that sent the notification
            // (Dunst sends ActionInvoked to the client that sent the notification)
            const linux_backend = @as(*linux.LinuxBackend, @alignCast(@ptrCast(platform_backend.ptr)));

            // Subscribe to ActionInvoked signals on this connection
            try linux_backend.addMatchRule();

            // Wait for action signal (timeout in milliseconds, 0 = infinite)
            const timeout_ms: u32 = config.wait_timeout orelse 0;
            var signal = linux_backend.waitForActionInvokedSignal(allocator, id, timeout_ms) catch |err| {
                if (err == error.Timeout) {
                    std.debug.print("Timeout waiting for action\n", .{});
                    return err;
                }
                return err;
            };
            defer signal.deinit(allocator);

            std.debug.print("Action invoked: {s}\n", .{signal.action_key});
        } else {
            std.debug.print("Wait mode is only supported on Linux\n", .{});
        }
    }
}
