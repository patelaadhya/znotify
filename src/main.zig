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
    const config = parser.parse() catch |err| {
        if (err == error.HelpRequested or err == error.VersionRequested) {
            return;
        }
        std.debug.print("Error parsing arguments: {}\n", .{err});
        try cli.printHelp();
        return err;
    };

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
        if (config.app_name) |a| notif.app_name = a;
        if (config.replace_id) |r| notif.replace_id = r;
        if (config.icon) |i| {
            // Try to parse as builtin icon first, otherwise treat as file path
            if (notification.BuiltinIcon.fromString(i)) |builtin| {
                notif.icon = .{ .builtin = builtin };
            } else |_| {
                const icon_path = try allocator.dupe(u8, i);
                notif.icon = .{ .file_path = icon_path };
            }
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
    if (config.app_name) |a| notif.app_name = a;
    if (config.replace_id) |r| notif.replace_id = r;
    if (config.icon) |i| {
        // Try to parse as builtin icon first, otherwise treat as file path
        if (notification.BuiltinIcon.fromString(i)) |builtin| {
            notif.icon = .{ .builtin = builtin };
        } else |_| {
            const icon_path = try allocator.dupe(u8, i);
            notif.icon = .{ .file_path = icon_path };
        }
    }

    const id = try platform_backend.send(notif);
    std.debug.print("Notification sent with ID: {}\n", .{id});

    const caps = try platform_backend.getCapabilities(allocator);
    defer allocator.free(caps);
    std.debug.print("Backend capabilities: {s}\n", .{caps});
}
