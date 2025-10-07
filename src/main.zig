const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = cli.ArgParser.init(allocator, args);
    const config = parser.parse() catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return;
    };

    if (config.help) {
        try cli.printHelp();
    } else if (config.version) {
        try cli.printVersion();
    } else {
        std.debug.print("Title: {?s}\n", .{config.title});
        std.debug.print("Message: {?s}\n", .{config.message});
        std.debug.print("Debug: {}\n", .{config.debug});
    }
}
