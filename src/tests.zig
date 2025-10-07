const std = @import("std");
const testing = std.testing;

test "build system works" {
    try testing.expect(true);
}

const notification = @import("notification.zig");

test "Urgency enum conversion" {
    try testing.expectEqual(notification.Urgency.low, try notification.Urgency.fromString("low"));
    try testing.expectEqual(notification.Urgency.critical, try notification.Urgency.fromString("critical"));
    try testing.expectError(error.InvalidUrgency, notification.Urgency.fromString("invalid"));
}

test "Notification creation and modification" {
    const allocator = testing.allocator;

    var notif = try notification.Notification.init(allocator, "Title", "Message");
    defer notif.deinit();

    try testing.expectEqualStrings("Title", notif.title);
    try testing.expectEqualStrings("Message", notif.message);
    try testing.expectEqual(notification.Urgency.normal, notif.urgency);

    notif.setUrgency(.critical);
    try testing.expectEqual(notification.Urgency.critical, notif.urgency);
}

test "Notification builder" {
    const allocator = testing.allocator;

    var builder = try notification.NotificationBuilder.init(allocator, "Test", "Builder");
    var notif = builder.urgency(.low).timeout(1000).build();
    defer notif.deinit();

    try testing.expectEqual(notification.Urgency.low, notif.urgency);
    try testing.expectEqual(@as(?u32, 1000), notif.timeout_ms);
}
