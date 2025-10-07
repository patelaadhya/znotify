const std = @import("std");
const notification = @import("notification.zig");
const errors = @import("errors.zig");

pub fn main() !void {
    // Test error reporting
    var reporter = errors.ErrorReporter.init(true);

    // Simulate an error
    const err = errors.ZNotifyError.InvalidIconPath;
    const context = errors.ErrorContext{
        .error_type = err,
        .message = "Icon not found",
        .details = "/invalid/path/icon.png",
    };

    reporter.reportError(err, context);
    reporter.reportWarning("This is a test warning");

    std.debug.print("Exit code for error: {}\n", .{errors.getExitCode(err)});
}
