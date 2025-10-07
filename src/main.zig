const std = @import("std");
const validation = @import("utils/validation.zig");
const escaping = @import("utils/escaping.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test validation
    const title = try validation.validateTitle("Test Title");
    std.debug.print("Valid title: {s}\n", .{title});

    // Test escaping
    const text = "Test <message> with \"quotes\" & special chars";
    const escaped = try validation.escapeXml(allocator, text);
    defer allocator.free(escaped);
    std.debug.print("Original: {s}\n", .{text});
    std.debug.print("Escaped: {s}\n", .{escaped});

    // Test truncation
    const long_text = "This is a very long text that needs to be truncated";
    const truncated = try validation.truncateString(allocator, long_text, 20);
    defer allocator.free(truncated);
    std.debug.print("Truncated: {s}\n", .{truncated});
}
