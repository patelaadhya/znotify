const std = @import("std");
const validation = @import("utils/validation.zig");
const escaping = @import("utils/escaping.zig");

/// Benchmark timing utility
const Timer = struct {
    start: i128,

    fn init() Timer {
        return .{ .start = std.time.nanoTimestamp() };
    }

    fn elapsed(self: Timer) u64 {
        const now = std.time.nanoTimestamp();
        return @intCast(now - self.start);
    }
};

/// Benchmark result
const BenchResult = struct {
    name: []const u8,
    iterations: usize,
    total_ns: u64,
    min_ns: u64,
    max_ns: u64,

    fn print(self: BenchResult) !void {
        const stdout = std.fs.File.stdout();
        var buf: [256]u8 = undefined;

        const mean_ns = self.total_ns / self.iterations;
        const ops_per_sec = (1_000_000_000 * self.iterations) / self.total_ns;

        const msg = try std.fmt.bufPrint(&buf,
            "{s:<40} | {:>8} ops/sec | mean: {:>6} us | min: {:>6} us | max: {:>6} us\n",
            .{
                self.name,
                ops_per_sec,
                mean_ns / 1000,
                self.min_ns / 1000,
                self.max_ns / 1000,
            },
        );
        _ = try stdout.write(msg);
    }
};

/// Run a benchmark and return results
fn runBench(
    comptime name: []const u8,
    iterations: usize,
    func: anytype,
    args: anytype,
) !BenchResult {
    var total_ns: u64 = 0;
    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const timer = Timer.init();
        _ = try @call(.auto, func, args);
        const elapsed_ns = timer.elapsed();

        total_ns += elapsed_ns;
        if (elapsed_ns < min_ns) min_ns = elapsed_ns;
        if (elapsed_ns > max_ns) max_ns = elapsed_ns;
    }

    return BenchResult{
        .name = name,
        .iterations = iterations,
        .total_ns = total_ns,
        .min_ns = min_ns,
        .max_ns = max_ns,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File.stdout();
    _ = try stdout.write(
        \\
        \\ZNotify Validation & Escaping Benchmarks
        \\========================================
        \\
    );

    // Generate test strings of various sizes
    const small_safe = "Hello World";
    const small_unsafe = "<test> & \"quotes\"";

    var medium_safe_buf: [100]u8 = undefined;
    @memset(&medium_safe_buf, 'a');
    const medium_safe = medium_safe_buf[0..];

    var medium_unsafe_buf: [100]u8 = undefined;
    for (&medium_unsafe_buf, 0..) |*c, i| {
        c.* = if (i % 2 == 0) '<' else '>';
    }
    const medium_unsafe = medium_unsafe_buf[0..];

    var large_safe_buf: [1000]u8 = undefined;
    @memset(&large_safe_buf, 'a');
    const large_safe = large_safe_buf[0..];

    var large_unsafe_buf: [1000]u8 = undefined;
    for (&large_unsafe_buf, 0..) |*c, i| {
        c.* = switch (i % 5) {
            0 => '<',
            1 => '>',
            2 => '&',
            3 => '"',
            else => 'a',
        };
    }
    const large_unsafe = large_unsafe_buf[0..];

    const shell_injection = "test; rm -rf / && echo 'pwned'";

    _ = try stdout.write("\n--- XML Escaping ---\n");

    // XML escaping benchmarks
    var result = try runBench("escapeXml: small safe (11 chars)", 100_000, struct {
        fn run(alloc: std.mem.Allocator, text: []const u8) !void {
            const escaped = try validation.escapeXml(alloc, text);
            defer alloc.free(escaped);
        }
    }.run, .{ allocator, small_safe });
    try result.print();

    result = try runBench("escapeXml: small unsafe (20 chars)", 100_000, struct {
        fn run(alloc: std.mem.Allocator, text: []const u8) !void {
            const escaped = try validation.escapeXml(alloc, text);
            defer alloc.free(escaped);
        }
    }.run, .{ allocator, small_unsafe });
    try result.print();

    result = try runBench("escapeXml: medium safe (100 chars)", 50_000, struct {
        fn run(alloc: std.mem.Allocator, text: []const u8) !void {
            const escaped = try validation.escapeXml(alloc, text);
            defer alloc.free(escaped);
        }
    }.run, .{ allocator, medium_safe });
    try result.print();

    result = try runBench("escapeXml: medium unsafe (100 chars)", 50_000, struct {
        fn run(alloc: std.mem.Allocator, text: []const u8) !void {
            const escaped = try validation.escapeXml(alloc, text);
            defer alloc.free(escaped);
        }
    }.run, .{ allocator, medium_unsafe });
    try result.print();

    result = try runBench("escapeXml: large safe (1000 chars)", 10_000, struct {
        fn run(alloc: std.mem.Allocator, text: []const u8) !void {
            const escaped = try validation.escapeXml(alloc, text);
            defer alloc.free(escaped);
        }
    }.run, .{ allocator, large_safe });
    try result.print();

    result = try runBench("escapeXml: large unsafe (1000 chars)", 10_000, struct {
        fn run(alloc: std.mem.Allocator, text: []const u8) !void {
            const escaped = try validation.escapeXml(alloc, text);
            defer alloc.free(escaped);
        }
    }.run, .{ allocator, large_unsafe });
    try result.print();

    _ = try stdout.write("\n--- Shell Escaping ---\n");

    result = try runBench("escapeShell: safe string", 100_000, struct {
        fn run(alloc: std.mem.Allocator) !void {
            const escaped = try escaping.escapeShell(alloc, "safe-file_name.txt");
            defer alloc.free(escaped);
        }
    }.run, .{allocator});
    try result.print();

    result = try runBench("escapeShell: injection attempt", 100_000, struct {
        fn run(alloc: std.mem.Allocator, text: []const u8) !void {
            const escaped = try escaping.escapeShell(alloc, text);
            defer alloc.free(escaped);
        }
    }.run, .{ allocator, shell_injection });
    try result.print();

    _ = try stdout.write("\n--- Validation ---\n");

    result = try runBench("validateTitle: valid", 100_000, struct {
        fn run() !void {
            _ = try validation.validateTitle("Valid Title");
        }
    }.run, .{});
    try result.print();

    result = try runBench("validateMessage: valid medium", 100_000, struct {
        fn run(text: []const u8) !void {
            _ = try validation.validateMessage(text);
        }
    }.run, .{medium_safe});
    try result.print();

    result = try runBench("validateMessage: valid large", 50_000, struct {
        fn run(text: []const u8) !void {
            _ = try validation.validateMessage(text);
        }
    }.run, .{large_safe});
    try result.print();

    result = try runBench("validateCategory: valid", 100_000, struct {
        fn run() !void {
            _ = try validation.validateCategory("app.notification.info");
        }
    }.run, .{});
    try result.print();

    result = try runBench("validateAppName: valid", 100_000, struct {
        fn run() !void {
            _ = try validation.validateAppName("ZNotify");
        }
    }.run, .{});
    try result.print();

    result = try runBench("isValidUtf8: ASCII", 100_000, struct {
        fn run() !void {
            _ = validation.isValidUtf8("Hello World");
        }
    }.run, .{});
    try result.print();

    result = try runBench("isValidUtf8: UTF-8 multibyte", 100_000, struct {
        fn run() !void {
            _ = validation.isValidUtf8("Hello 世界 🌍");
        }
    }.run, .{});
    try result.print();

    _ = try stdout.write("\n--- String Operations ---\n");

    result = try runBench("truncateString: no truncation needed", 100_000, struct {
        fn run(alloc: std.mem.Allocator) !void {
            const truncated = try validation.truncateString(alloc, "Short", 20);
            defer alloc.free(truncated);
        }
    }.run, .{allocator});
    try result.print();

    result = try runBench("truncateString: truncation required", 100_000, struct {
        fn run(alloc: std.mem.Allocator, text: []const u8) !void {
            const truncated = try validation.truncateString(alloc, text, 50);
            defer alloc.free(truncated);
        }
    }.run, .{ allocator, large_safe });
    try result.print();

    _ = try stdout.write(
        \\
        \\--- Security Edge Cases ---
        \\
    );

    // Test path traversal detection
    const traversal_attempts = [_][]const u8{
        "../etc/passwd",
        "..\\windows\\system32",
        "../../../../../../etc/shadow",
    };

    var traversal_caught: usize = 0;
    for (traversal_attempts) |attempt| {
        validation.validateIconPath(attempt) catch {
            traversal_caught += 1;
        };
    }

    var msg_buf: [128]u8 = undefined;
    const msg = try std.fmt.bufPrint(&msg_buf,
        "Path traversal detection: {}/{} caught\n",
        .{ traversal_caught, traversal_attempts.len },
    );
    _ = try stdout.write(msg);

    // Test control character detection
    const control_chars = [_]u8{ 0x00, 0x01, 0x02, 0x1F };
    var control_caught: usize = 0;
    for (control_chars) |c| {
        const test_str = [_]u8{ 'A', c, 'B' };
        _ = validation.validateTitle(&test_str) catch {
            control_caught += 1;
            continue;
        };
    }

    const msg2 = try std.fmt.bufPrint(&msg_buf,
        "Control character detection: {}/{} caught\n",
        .{ control_caught, control_chars.len },
    );
    _ = try stdout.write(msg2);

    // Test length limits
    var too_long_title: [101]u8 = undefined;
    @memset(&too_long_title, 'A');
    const title_result = validation.validateTitle(&too_long_title);
    const title_limit_works = if (title_result) |_| false else |_| true;

    var too_long_message: [1001]u8 = undefined;
    @memset(&too_long_message, 'A');
    const message_result = validation.validateMessage(&too_long_message);
    const message_limit_works = if (message_result) |_| false else |_| true;

    const msg3 = try std.fmt.bufPrint(&msg_buf,
        "Length limit enforcement: title={} message={}\n",
        .{ title_limit_works, message_limit_works },
    );
    _ = try stdout.write(msg3);

    _ = try stdout.write(
        \\
        \\Benchmarks complete!
        \\
    );
}
