const std = @import("std");
const errors = @import("../errors.zig");

/// Maximum allowed lengths and values for notification fields.
/// These limits protect against resource exhaustion and ensure
/// compatibility with notification daemon constraints.
pub const Limits = struct {
    pub const max_title_length: usize = 100;
    pub const max_message_length: usize = 1000;
    pub const max_category_length: usize = 50;
    pub const max_app_name_length: usize = 50;
    pub const max_path_length: usize = 4096;
    pub const max_timeout_ms: u32 = 3600000; // 1 hour
};

/// Validates notification title for length and control characters.
///
/// Returns the title unchanged if valid, otherwise returns an error.
/// Checks: empty strings, excessive length, invalid control characters.
///
/// Parameters:
///   - title: The notification title to validate
///
/// Returns: The validated title slice (unchanged)
///
/// Errors:
///   - error.MissingRequiredField if title is empty
///   - error.TitleTooLong if exceeds max_title_length
///   - error.InvalidArgument if contains invalid control characters
pub fn validateTitle(title: []const u8) ![]const u8 {
    if (title.len == 0) {
        return errors.ZNotifyError.MissingRequiredField;
    }

    if (title.len > Limits.max_title_length) {
        return errors.ZNotifyError.TitleTooLong;
    }

    // Check for control characters
    for (title) |c| {
        if (c < 0x20 and c != '\t' and c != '\n') {
            return errors.ZNotifyError.InvalidArgument;
        }
    }

    return title;
}

/// Validates notification message for length and control characters.
///
/// Allows newlines and tabs but rejects other control characters.
///
/// Parameters:
///   - message: The notification message body to validate
///
/// Returns: The validated message slice (unchanged)
///
/// Errors:
///   - error.MessageTooLong if exceeds max_message_length
///   - error.InvalidArgument if contains invalid control characters
pub fn validateMessage(message: []const u8) ![]const u8 {
    if (message.len > Limits.max_message_length) {
        return errors.ZNotifyError.MessageTooLong;
    }

    // Check for control characters (except newline and tab)
    for (message) |c| {
        if (c < 0x20 and c != '\t' and c != '\n' and c != '\r') {
            return errors.ZNotifyError.InvalidArgument;
        }
    }

    return message;
}

/// Validates timeout value is within acceptable range.
///
/// Parameters:
///   - timeout_ms: Timeout in milliseconds (0 = persistent)
///
/// Returns: The timeout value if valid
///
/// Errors:
///   - error.InvalidTimeout if exceeds max_timeout_ms (1 hour)
pub fn validateTimeout(timeout_ms: u32) !u32 {
    if (timeout_ms > Limits.max_timeout_ms) {
        return errors.ZNotifyError.InvalidTimeout;
    }
    return timeout_ms;
}

/// Validates icon file path for security and existence.
///
/// Performs security checks for path traversal attempts and verifies
/// file existence for absolute paths. Built-in icon names are allowed.
///
/// Parameters:
///   - path: Icon path or built-in icon name
///
/// Errors:
///   - error.InvalidIconPath if empty or too long
///   - error.InvalidFilePath if path traversal detected (../)
///   - error.FileNotFound if absolute path doesn't exist
pub fn validateIconPath(path: []const u8) !void {
    if (path.len == 0) {
        return errors.ZNotifyError.InvalidIconPath;
    }

    if (path.len > Limits.max_path_length) {
        return errors.ZNotifyError.InvalidIconPath;
    }

    // Check for path traversal attempts
    if (std.mem.indexOf(u8, path, "../") != null or
        std.mem.indexOf(u8, path, "..\\") != null)
    {
        return errors.ZNotifyError.InvalidFilePath;
    }

    // If it's a file path (not a built-in icon), check if it exists
    if (path[0] == '/' or path[0] == '\\' or
        (path.len > 2 and path[1] == ':')) // Windows drive letter
    {
        const file = std.fs.openFileAbsolute(path, .{}) catch {
            return errors.ZNotifyError.FileNotFound;
        };
        file.close();
    }
}

/// Validates notification category name format.
///
/// Categories must be alphanumeric with dots, dashes, and underscores only.
/// Used for filtering/organizing notifications by type.
///
/// Parameters:
///   - category: Category name to validate
///
/// Returns: The validated category slice (unchanged)
///
/// Errors:
///   - error.InvalidArgument if exceeds max length or contains invalid characters
pub fn validateCategory(category: []const u8) ![]const u8 {
    if (category.len > Limits.max_category_length) {
        return errors.ZNotifyError.InvalidArgument;
    }

    // Category should be alphanumeric with dots and dashes
    for (category) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '-' and c != '_') {
            return errors.ZNotifyError.InvalidArgument;
        }
    }

    return category;
}

/// Validates application name for safety and length.
///
/// App name must be non-empty, within length limits, and not contain
/// XML/HTML special characters that could cause injection issues.
///
/// Parameters:
///   - app_name: Application name to validate
///
/// Returns: The validated app name slice (unchanged)
///
/// Errors:
///   - error.InvalidArgument if empty, too long, or contains special characters
pub fn validateAppName(app_name: []const u8) ![]const u8 {
    if (app_name.len == 0) {
        return errors.ZNotifyError.InvalidArgument;
    }

    if (app_name.len > Limits.max_app_name_length) {
        return errors.ZNotifyError.InvalidArgument;
    }

    // App name should not contain special characters
    for (app_name) |c| {
        if (!std.ascii.isPrint(c) or c == '<' or c == '>' or c == '&' or c == '"') {
            return errors.ZNotifyError.InvalidArgument;
        }
    }

    return app_name;
}

/// Escapes HTML/XML special characters to prevent injection attacks.
///
/// Converts: < > & " ' to their XML entity equivalents.
/// Uses two-pass algorithm: count required space, then escape.
/// Returns original string copy if no escaping needed (optimization).
///
/// Parameters:
///   - allocator: Memory allocator for result
///   - text: Input text to escape
///
/// Returns: Newly allocated escaped string (caller must free)
///
/// Performance: O(n) time, allocates only if escaping needed
pub fn escapeXml(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var count: usize = 0;

    // First pass: count how much space we need
    for (text) |c| {
        count += switch (c) {
            '<' => "&lt;".len,
            '>' => "&gt;".len,
            '&' => "&amp;".len,
            '"' => "&quot;".len,
            '\'' => "&apos;".len,
            else => 1,
        };
    }

    if (count == text.len) {
        // No escaping needed
        return allocator.dupe(u8, text);
    }

    // Second pass: perform escaping
    var result = try allocator.alloc(u8, count);
    var i: usize = 0;

    for (text) |c| {
        const replacement = switch (c) {
            '<' => "&lt;",
            '>' => "&gt;",
            '&' => "&amp;",
            '"' => "&quot;",
            '\'' => "&apos;",
            else => {
                result[i] = c;
                i += 1;
                continue;
            },
        };

        @memcpy(result[i .. i + replacement.len], replacement);
        i += replacement.len;
    }

    return result;
}

/// Validates all fields of a complete notification.
///
/// Performs validation on title, message, timeout, category, and app name.
/// Should be called before sending notification to ensure all constraints met.
///
/// Parameters:
///   - notif: Notification struct with fields to validate
///
/// Errors: Any validation error from individual field validators
pub fn validateNotification(notif: anytype) !void {
    _ = try validateTitle(notif.title);
    _ = try validateMessage(notif.message);

    if (notif.timeout_ms) |timeout| {
        _ = try validateTimeout(timeout);
    }

    if (notif.category) |category| {
        _ = try validateCategory(category);
    }

    _ = try validateAppName(notif.app_name);
}

/// Truncates string to maximum length, adding ellipsis if needed.
///
/// If text fits within max_len, returns a copy unchanged.
/// Otherwise, truncates and appends "..." within the max_len limit.
///
/// Parameters:
///   - allocator: Memory allocator for result
///   - text: Input text to truncate
///   - max_len: Maximum length including ellipsis
///
/// Returns: Newly allocated truncated string (caller must free)
pub fn truncateString(allocator: std.mem.Allocator, text: []const u8, max_len: usize) ![]u8 {
    if (text.len <= max_len) {
        return allocator.dupe(u8, text);
    }

    const ellipsis = "...";
    if (max_len < ellipsis.len) {
        return allocator.dupe(u8, text[0..max_len]);
    }

    var result = try allocator.alloc(u8, max_len);
    const text_len = max_len - ellipsis.len;
    @memcpy(result[0..text_len], text[0..text_len]);
    @memcpy(result[text_len..], ellipsis);

    return result;
}

/// Checks if string contains valid UTF-8 encoding.
///
/// Parameters:
///   - text: Byte slice to validate
///
/// Returns: true if valid UTF-8, false otherwise
pub fn isValidUtf8(text: []const u8) bool {
    return std.unicode.utf8ValidateSlice(text);
}
