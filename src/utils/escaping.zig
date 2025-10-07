const std = @import("std");

/// Escapes string for safe shell command execution.
///
/// Uses single-quote wrapping with proper quote escaping to prevent
/// shell injection attacks. Returns unmodified copy if no escaping needed.
///
/// Escaping strategy: Wraps in single quotes, escapes embedded quotes as '\''
///
/// Parameters:
///   - allocator: Memory allocator for result
///   - text: Input text to escape
///
/// Returns: Newly allocated shell-safe string (caller must free)
///
/// Performance: O(n) time, only allocates if escaping needed
pub fn escapeShell(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var need_escape = false;
    for (text) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_' and c != '.' and c != '/') {
            need_escape = true;
            break;
        }
    }

    if (!need_escape) {
        return allocator.dupe(u8, text);
    }

    // Use single quotes and escape single quotes
    var size: usize = 2; // For surrounding quotes
    for (text) |c| {
        if (c == '\'') {
            size += 4; // '\'' becomes '\''\'\'
        } else {
            size += 1;
        }
    }

    var result = try allocator.alloc(u8, size);
    var i: usize = 0;
    result[i] = '\'';
    i += 1;

    for (text) |c| {
        if (c == '\'') {
            @memcpy(result[i .. i + 4], "'\\''");
            i += 4;
        } else {
            result[i] = c;
            i += 1;
        }
    }

    result[i] = '\'';
    return result;
}

/// Escapes string for D-Bus notification messages.
///
/// D-Bus uses XML format, so delegates to XML escaping.
///
/// Parameters:
///   - allocator: Memory allocator for result
///   - text: Input text to escape
///
/// Returns: Newly allocated XML-escaped string (caller must free)
pub fn escapeDBus(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    // D-Bus uses standard XML escaping
    return @import("validation.zig").escapeXml(allocator, text);
}

/// Escapes string for Windows toast notification XML.
///
/// Windows toast notifications use XML format, so delegates to XML escaping.
///
/// Parameters:
///   - allocator: Memory allocator for result
///   - text: Input text to escape
///
/// Returns: Newly allocated XML-escaped string (caller must free)
pub fn escapeWindowsToast(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    // Windows toast uses XML format
    return @import("validation.zig").escapeXml(allocator, text);
}

/// Escapes string for macOS notification AppleScript.
///
/// Escapes backslashes and double quotes for AppleScript string literals.
/// Returns unmodified copy if no escaping needed.
///
/// Parameters:
///   - allocator: Memory allocator for result
///   - text: Input text to escape
///
/// Returns: Newly allocated escaped string (caller must free)
pub fn escapeMacOS(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    // macOS notifications handle most characters well
    // Just escape quotes for AppleScript if needed
    var count: usize = 0;
    for (text) |c| {
        count += if (c == '"' or c == '\\') 2 else 1;
    }

    if (count == text.len) {
        return allocator.dupe(u8, text);
    }

    var result = try allocator.alloc(u8, count);
    var i: usize = 0;
    for (text) |c| {
        if (c == '"' or c == '\\') {
            result[i] = '\\';
            i += 1;
        }
        result[i] = c;
        i += 1;
    }

    return result;
}
