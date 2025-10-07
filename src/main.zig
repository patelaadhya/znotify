const std = @import("std");
const notification = @import("notification.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var notif = try notification.Notification.init(allocator, "Test", "Message");
    defer notif.deinit();

    std.debug.print("Notification created: {s}\n", .{notif.title});

    // Test builder
    var builder = try notification.NotificationBuilder.init(allocator, "Builder", "Test");
    var built = builder.urgency(.critical).timeout(10000).build();
    defer built.deinit();

    std.debug.print("Builder notification urgency: {s}\n", .{built.urgency.toString()});
}
