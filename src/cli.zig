const std = @import("std");
const notification = @import("notification.zig");
const errors = @import("errors.zig");
const build_options = @import("build_options");

/// Action button configuration (id and label pair)
pub const ActionConfig = struct {
    id: []const u8,
    label: []const u8,
};

/// Command-line configuration
pub const Config = struct {
    // Positional arguments
    title: ?[]const u8 = null,
    message: ?[]const u8 = null,

    // Optional flags
    urgency: ?notification.Urgency = null,
    timeout_ms: ?u32 = null,
    icon: ?[]const u8 = null,
    category: ?[]const u8 = null,
    app_name: ?[]const u8 = null,
    replace_id: ?u32 = null,
    actions: std.ArrayList(ActionConfig) = undefined,

    // Behavior flags
    print_id: bool = false,
    wait: bool = false,
    wait_timeout: ?u32 = null, // Timeout in milliseconds for --wait mode (null = infinite)
    no_sound: bool = false,
    dry_run: bool = false,
    debug: bool = build_options.enable_debug,

    // Special commands
    help: bool = false,
    version: bool = false,
    doctor: bool = false,
    init_config: bool = false,
    compat_mode: bool = false,

    // Config file path
    config_file: ?[]const u8 = null,

    allocator: std.mem.Allocator,

    /// Deinitializes the configuration and frees any allocated resources.
    /// Currently, most strings are slices from argv and don't require freeing.
    pub fn deinit(self: *Config) void {
        // Free actions ArrayList
        self.actions.deinit(self.allocator);
    }
};

/// Argument parser
pub const ArgParser = struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
    current: usize = 1, // Skip program name
    config: Config,

    /// Creates a new argument parser for the given command-line arguments.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for any required allocations
    ///   - args: Command-line arguments array (typically from std.process.argsAlloc)
    pub fn init(allocator: std.mem.Allocator, args: []const []const u8) ArgParser {
        const config = Config{
            .allocator = allocator,
            .actions = .{},
        };
        return ArgParser{
            .allocator = allocator,
            .args = args,
            .config = config,
        };
    }

    /// Parses all command-line arguments and returns a populated Config.
    ///
    /// This function processes:
    /// - Long options (--option or --option=value)
    /// - Short options (-o or combined -abc)
    /// - Positional arguments (title and message)
    /// - Automatic notify-send compatibility mode detection
    ///
    /// Returns:
    ///   - Config with all parsed values
    ///   - error.MissingRequiredField if title is missing (except for special commands)
    ///   - error.InvalidArgument for unrecognized options or too many positional args
    pub fn parse(self: *ArgParser) !Config {
        // Check for compatibility mode (when called as notify-send)
        if (self.args.len > 0) {
            const program_name = std.fs.path.basename(self.args[0]);
            if (std.mem.eql(u8, program_name, "notify-send")) {
                self.config.compat_mode = true;
            }
        }

        while (self.current < self.args.len) {
            const arg = self.args[self.current];

            if (std.mem.startsWith(u8, arg, "--")) {
                try self.parseLongOption(arg[2..]);
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                try self.parseShortOption(arg[1..]);
            } else {
                // Positional argument
                if (self.config.title == null) {
                    self.config.title = arg;
                } else if (self.config.message == null) {
                    self.config.message = arg;
                } else {
                    return errors.ZNotifyError.InvalidArgument;
                }
            }

            self.current += 1;
        }

        // Validate required fields
        if (!self.config.help and !self.config.version and !self.config.doctor and !self.config.init_config) {
            if (self.config.title == null) {
                return errors.ZNotifyError.MissingRequiredField;
            }
        }

        return self.config;
    }

    /// Parses a long option (without the leading --).
    ///
    /// Handles both formats:
    /// - Flag-style: --help, --version, --debug
    /// - Value-style: --timeout=5000 or --timeout 5000
    ///
    /// Parameters:
    ///   - option: The option string without the -- prefix
    fn parseLongOption(self: *ArgParser, option: []const u8) !void {
        if (std.mem.eql(u8, option, "help")) {
            self.config.help = true;
        } else if (std.mem.eql(u8, option, "version")) {
            self.config.version = true;
        } else if (std.mem.eql(u8, option, "doctor")) {
            self.config.doctor = true;
        } else if (std.mem.eql(u8, option, "init-config")) {
            self.config.init_config = true;
        } else if (std.mem.eql(u8, option, "debug")) {
            self.config.debug = true;
        } else if (std.mem.eql(u8, option, "dry-run")) {
            self.config.dry_run = true;
        } else if (std.mem.eql(u8, option, "print-id")) {
            self.config.print_id = true;
        } else if (std.mem.eql(u8, option, "wait")) {
            self.config.wait = true;
        } else if (std.mem.startsWith(u8, option, "wait-timeout=")) {
            const value = option["wait-timeout=".len..];
            self.config.wait_timeout = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, option, "no-sound")) {
            self.config.no_sound = true;
        } else if (std.mem.eql(u8, option, "compat")) {
            self.config.compat_mode = true;
        } else if (std.mem.startsWith(u8, option, "timeout=")) {
            const value = option[8..];
            self.config.timeout_ms = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.startsWith(u8, option, "urgency=")) {
            const value = option[8..];
            self.config.urgency = try notification.Urgency.fromString(value);
        } else if (std.mem.startsWith(u8, option, "icon=")) {
            self.config.icon = option[5..];
        } else if (std.mem.startsWith(u8, option, "category=")) {
            self.config.category = option[9..];
        } else if (std.mem.startsWith(u8, option, "app-name=")) {
            self.config.app_name = option[9..];
        } else if (std.mem.startsWith(u8, option, "replace-id=")) {
            const value = option[11..];
            self.config.replace_id = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.startsWith(u8, option, "config=")) {
            self.config.config_file = option[7..];
        } else if (std.mem.eql(u8, option, "action")) {
            // --action takes two arguments: id and label
            self.current += 1;
            if (self.current >= self.args.len) {
                return errors.ZNotifyError.InvalidArgument;
            }
            const action_id = self.args[self.current];

            self.current += 1;
            if (self.current >= self.args.len) {
                return errors.ZNotifyError.InvalidArgument;
            }
            const action_label = self.args[self.current];

            try self.config.actions.append(self.allocator, ActionConfig{
                .id = action_id,
                .label = action_label,
            });
        } else {
            // Handle options with separate values
            if (std.mem.eql(u8, option, "timeout") or
                std.mem.eql(u8, option, "urgency") or
                std.mem.eql(u8, option, "icon") or
                std.mem.eql(u8, option, "category") or
                std.mem.eql(u8, option, "app-name") or
                std.mem.eql(u8, option, "replace-id") or
                std.mem.eql(u8, option, "config"))
            {
                self.current += 1;
                if (self.current >= self.args.len) {
                    return errors.ZNotifyError.InvalidArgument;
                }

                const value = self.args[self.current];
                try self.setOptionValue(option, value);
            } else {
                return errors.ZNotifyError.InvalidArgument;
            }
        }
    }

    /// Parses a short option (without the leading -).
    ///
    /// Handles:
    /// - Single flags: -h, -v, -p
    /// - Combined flags: -hvp (equivalent to -h -v -p)
    /// - Options with values: -t 5000, -u critical
    ///
    /// Parameters:
    ///   - option: The option string without the - prefix
    fn parseShortOption(self: *ArgParser, option: []const u8) !void {
        // Handle combined short options like -abc
        for (option) |opt| {
            switch (opt) {
                'h' => self.config.help = true,
                'v' => self.config.version = true,
                'p' => self.config.print_id = true,
                'w' => self.config.wait = true,
                'd' => self.config.debug = true,
                't', 'u', 'i', 'c', 'a', 'r' => {
                    // These require values
                    if (option.len > 1) {
                        return errors.ZNotifyError.InvalidArgument;
                    }
                    self.current += 1;
                    if (self.current >= self.args.len) {
                        return errors.ZNotifyError.InvalidArgument;
                    }
                    const value = self.args[self.current];
                    try self.setShortOptionValue(opt, value);
                },
                else => return errors.ZNotifyError.InvalidArgument,
            }
        }
    }

    /// Sets the configuration value for a long option.
    ///
    /// Parameters:
    ///   - option: The option name (e.g., "timeout", "urgency")
    ///   - value: The option value as a string
    fn setOptionValue(self: *ArgParser, option: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, option, "timeout")) {
            self.config.timeout_ms = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, option, "urgency")) {
            self.config.urgency = try notification.Urgency.fromString(value);
        } else if (std.mem.eql(u8, option, "icon")) {
            self.config.icon = value;
        } else if (std.mem.eql(u8, option, "category")) {
            self.config.category = value;
        } else if (std.mem.eql(u8, option, "app-name")) {
            self.config.app_name = value;
        } else if (std.mem.eql(u8, option, "replace-id")) {
            self.config.replace_id = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, option, "config")) {
            self.config.config_file = value;
        }
    }

    /// Sets the configuration value for a short option.
    ///
    /// Parameters:
    ///   - option: The short option character (e.g., 't', 'u', 'i')
    ///   - value: The option value as a string
    fn setShortOptionValue(self: *ArgParser, option: u8, value: []const u8) !void {
        switch (option) {
            't' => self.config.timeout_ms = try std.fmt.parseInt(u32, value, 10),
            'u' => self.config.urgency = try notification.Urgency.fromString(value),
            'i' => self.config.icon = value,
            'c' => self.config.category = value,
            'a' => self.config.app_name = value,
            'r' => self.config.replace_id = try std.fmt.parseInt(u32, value, 10),
            else => return errors.ZNotifyError.InvalidArgument,
        }
    }
};

/// Print help text
pub fn printHelp() !void {
    const stdout = std.fs.File.stdout();
    _ = try stdout.write(
        \\ZNotify - Cross-platform desktop notification utility
        \\
        \\USAGE:
        \\    znotify [OPTIONS] <title> [message]
        \\
        \\ARGUMENTS:
        \\    <title>     Notification title (required)
        \\    [message]   Notification message body (optional)
        \\
        \\OPTIONS:
        \\    -t, --timeout <ms>        Notification display time in milliseconds (0 = persistent)
        \\    -u, --urgency <level>     Set urgency: low|normal|critical
        \\    -i, --icon <icon>         Icon: info|warning|error|success|<path>
        \\    -c, --category <cat>      Notification category
        \\    -a, --app-name <name>     Application name (default: znotify)
        \\    -r, --replace-id <id>     Replace existing notification by ID
        \\        --action <id> <label> Add action button (can be repeated)
        \\    -p, --print-id            Print notification ID to stdout
        \\    -w, --wait                Wait for user interaction
        \\        --wait-timeout=<ms>   Timeout for wait mode in milliseconds
        \\        --no-sound            Disable notification sound
        \\        --config <file>       Use configuration file
        \\        --dry-run             Validate without sending notification
        \\        --debug               Enable debug output
        \\        --compat              Enable notify-send compatibility mode
        \\
        \\SPECIAL COMMANDS:
        \\    -h, --help                Show this help message
        \\    -v, --version             Show version information
        \\        --doctor              Check system compatibility
        \\        --init-config         Create default configuration file
        \\
        \\EXAMPLES:
        \\    # Simple notification
        \\    znotify "Hello" "This is a test"
        \\
        \\    # Urgent notification with icon
        \\    znotify -u critical -i error "Error" "Build failed"
        \\
        \\    # Timed notification
        \\    znotify -t 10000 "Reminder" "Meeting in 10 minutes"
        \\
        \\    # Replace previous notification
        \\    ID=$(znotify -p "Progress" "Starting...")
        \\    znotify -r $ID "Progress" "50% complete"
        \\
        \\    # Notification with action buttons
        \\    znotify --action yes "Accept" --action no "Decline" "Confirm" "Apply changes?"
        \\
        );
}

/// Print version information
pub fn printVersion() !void {
    const stdout = std.fs.File.stdout();
    var buf: [256]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf,
        \\znotify version 0.1.0
        \\Built with Zig {s}
        \\Platform: {s}-{s}
        \\
        , .{
        @import("builtin").zig_version_string,
        @tagName(@import("builtin").os.tag),
        @tagName(@import("builtin").cpu.arch),
    });
    _ = try stdout.write(msg);
}
