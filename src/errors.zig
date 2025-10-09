const std = @import("std");

/// All possible ZNotify errors
pub const ZNotifyError = error{
    // Initialization errors
    PlatformNotSupported,
    BackendInitFailed,
    NoNotificationService,
    ServiceConnectionFailed,

    // Input errors
    InvalidArgument,
    MissingRequiredField,
    InvalidIconPath,
    InvalidTimeout,
    InvalidUrgency,
    MessageTooLong,
    TitleTooLong,

    // Runtime errors
    NotificationFailed,
    QueueFull,
    ServiceUnavailable,
    PermissionDenied,
    TimeoutExceeded,

    // Platform-specific
    DBusConnectionFailed,
    DBusMethodCallFailed,
    WindowsRuntimeError,
    WindowsCOMError,
    MacOSAuthorizationDenied,
    MacOSFrameworkError,
    AuthorizationDenied,
    AuthorizationNotDetermined,

    // File system errors
    FileNotFound,
    FileAccessDenied,
    InvalidFilePath,

    // Configuration errors
    ConfigParseError,
    InvalidConfiguration,
    ConfigFileNotFound,

    // Memory errors
    OutOfMemory,
    AllocationFailed,
};

/// Error context for detailed reporting
pub const ErrorContext = struct {
    error_type: ZNotifyError,
    message: []const u8,
    details: ?[]const u8 = null,
    platform_code: ?i32 = null,

    /// Custom formatter for ErrorContext that outputs a structured error message.
    /// Formats as: "message (details) [code: platform_code]"
    /// Both details and platform_code are optional and only shown if present.
    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try std.fmt.format(writer, "{s}", .{self.message});
        if (self.details) |details| {
            try std.fmt.format(writer, " ({s})", .{details});
        }
        if (self.platform_code) |code| {
            try std.fmt.format(writer, " [code: {}]", .{code});
        }
    }
};

/// Error reporter for consistent error output
pub const ErrorReporter = struct {
    use_color: bool,
    debug_mode: bool,

    const Color = struct {
        const red = "\x1b[31m";
        const yellow = "\x1b[33m";
        const reset = "\x1b[0m";
        const bold = "\x1b[1m";
    };

    /// Creates a new ErrorReporter with automatic color detection.
    /// Color output is enabled automatically if stderr is connected to a TTY.
    ///
    /// Parameters:
    ///   - debug_mode: If true, stack traces will be printed with errors
    pub fn init(debug_mode: bool) ErrorReporter {
        const stderr_file = std.fs.File.stderr();
        const use_color = stderr_file.isTty();

        return ErrorReporter{
            .use_color = use_color,
            .debug_mode = debug_mode,
        };
    }

    /// Prints a formatted error message to stderr with optional context.
    ///
    /// Outputs:
    ///   - Colored "Error:" prefix (if TTY detected)
    ///   - Error message from context (if provided) or error name
    ///   - Remediation suggestion (if available for this error type)
    ///   - Stack trace (if debug_mode is enabled)
    ///
    /// Parameters:
    ///   - err: The error type that occurred
    ///   - context: Optional error context with detailed message, details, and platform code
    pub fn reportError(self: *ErrorReporter, err: ZNotifyError, context: ?ErrorContext) void {
        const stderr_file = std.fs.File.stderr();

        // Write error message
        if (self.use_color) {
            _ = stderr_file.write(Color.bold) catch {};
            _ = stderr_file.write(Color.red) catch {};
            _ = stderr_file.write("Error:") catch {};
            _ = stderr_file.write(Color.reset) catch {};
            _ = stderr_file.write(" ") catch {};
        } else {
            _ = stderr_file.write("Error: ") catch {};
        }

        if (context) |ctx| {
            var buf: [512]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            const writer = fbs.writer();
            ctx.format("", .{}, writer) catch {};
            const msg = fbs.getWritten();
            _ = stderr_file.write(msg) catch {};
            _ = stderr_file.write("\n") catch {};
        } else {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{s}\n", .{@errorName(err)}) catch "Unknown error\n";
            _ = stderr_file.write(msg) catch {};
        }

        // Print remediation suggestions
        const suggestion = getRemediationSuggestion(err);
        if (suggestion) |sug| {
            if (self.use_color) {
                _ = stderr_file.write(Color.yellow) catch {};
                _ = stderr_file.write("Suggestion:") catch {};
                _ = stderr_file.write(Color.reset) catch {};
                _ = stderr_file.write(" ") catch {};
                _ = stderr_file.write(sug) catch {};
                _ = stderr_file.write("\n") catch {};
            } else {
                _ = stderr_file.write("Suggestion: ") catch {};
                _ = stderr_file.write(sug) catch {};
                _ = stderr_file.write("\n") catch {};
            }
        }

        if (self.debug_mode) {
            // Print stack trace in debug mode
            _ = stderr_file.write("\nDebug info:\n") catch {};
            std.debug.dumpCurrentStackTrace(null);
        }
    }

    /// Prints a formatted warning message to stderr.
    ///
    /// Outputs a colored "Warning:" prefix (if TTY detected) followed by the message.
    ///
    /// Parameters:
    ///   - message: The warning message to display
    pub fn reportWarning(self: *ErrorReporter, message: []const u8) void {
        const stderr_file = std.fs.File.stderr();

        if (self.use_color) {
            _ = stderr_file.write(Color.yellow) catch {};
            _ = stderr_file.write("Warning:") catch {};
            _ = stderr_file.write(Color.reset) catch {};
            _ = stderr_file.write(" ") catch {};
            _ = stderr_file.write(message) catch {};
            _ = stderr_file.write("\n") catch {};
        } else {
            _ = stderr_file.write("Warning: ") catch {};
            _ = stderr_file.write(message) catch {};
            _ = stderr_file.write("\n") catch {};
        }
    }
};

/// Get remediation suggestion for an error
pub fn getRemediationSuggestion(err: ZNotifyError) ?[]const u8 {
    return switch (err) {
        error.PlatformNotSupported => "This platform is not yet supported. Please check the documentation for supported platforms.",
        error.NoNotificationService => "No notification service is running. Please start your desktop environment's notification daemon.",
        error.PermissionDenied => "Notification permission was denied. Please grant notification access in your system settings.",
        error.InvalidIconPath => "The specified icon path is invalid or the file doesn't exist. Use --help to see available built-in icons.",
        error.InvalidUrgency => "Invalid urgency level. Use: low, normal, or critical.",
        error.InvalidTimeout => "Invalid timeout value. Use a positive number in milliseconds, or 0 for persistent notifications.",
        error.MessageTooLong => "Message is too long. Please limit to 1000 characters.",
        error.TitleTooLong => "Title is too long. Please limit to 100 characters.",
        error.DBusConnectionFailed => "Failed to connect to D-Bus. Ensure D-Bus daemon is running: systemctl --user status dbus",
        error.WindowsCOMError => "Windows COM initialization failed. This is usually a system issue. Try restarting.",
        error.MacOSAuthorizationDenied => "macOS notification authorization denied. Grant permission in System Preferences > Notifications.",
        error.AuthorizationDenied => "Notification authorization denied. Grant permission in system settings.",
        error.AuthorizationNotDetermined => "Notification authorization not determined. Please run the app first to request permission.",
        error.ConfigFileNotFound => "Configuration file not found. Run 'znotify --init-config' to create a default configuration.",
        error.OutOfMemory => "System is out of memory. Close some applications and try again.",
        else => null,
    };
}

/// Exit codes for different error categories
pub fn getExitCode(err: ZNotifyError) u8 {
    return switch (err) {
        // Initialization errors (10-19)
        error.PlatformNotSupported => 10,
        error.BackendInitFailed => 11,
        error.NoNotificationService => 12,
        error.ServiceConnectionFailed => 13,

        // Input errors (20-29)
        error.InvalidArgument => 20,
        error.MissingRequiredField => 21,
        error.InvalidIconPath => 22,
        error.InvalidTimeout => 23,
        error.InvalidUrgency => 24,
        error.MessageTooLong => 25,
        error.TitleTooLong => 26,

        // Runtime errors (30-39)
        error.NotificationFailed => 30,
        error.QueueFull => 31,
        error.ServiceUnavailable => 32,
        error.PermissionDenied => 33,
        error.TimeoutExceeded => 34,

        // Platform-specific (40-49)
        error.DBusConnectionFailed => 40,
        error.DBusMethodCallFailed => 41,
        error.WindowsRuntimeError => 42,
        error.WindowsCOMError => 43,
        error.MacOSAuthorizationDenied => 44,
        error.MacOSFrameworkError => 45,
        error.AuthorizationDenied => 46,
        error.AuthorizationNotDetermined => 47,

        // File system errors (50-59)
        error.FileNotFound => 50,
        error.FileAccessDenied => 51,
        error.InvalidFilePath => 52,

        // Configuration errors (60-69)
        error.ConfigParseError => 60,
        error.InvalidConfiguration => 61,
        error.ConfigFileNotFound => 62,

        // Memory errors (70-79)
        error.OutOfMemory => 70,
        error.AllocationFailed => 71,
    };
}
