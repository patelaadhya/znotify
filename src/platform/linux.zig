const std = @import("std");
const notification = @import("../notification.zig");
const errors = @import("../errors.zig");
const backend = @import("backend.zig");
const validation = @import("../utils/validation.zig");
const net = std.net;
const fs = std.fs;

/// Linux notification backend using D-Bus protocol.
///
/// Communicates with desktop notification daemons via the
/// org.freedesktop.Notifications D-Bus interface. Compatible with:
/// - GNOME (gnome-shell notification daemon)
/// - KDE Plasma (plasma-workspace)
/// - Dunst
/// - Mako
/// - notify-osd
/// - XFCE4-notifyd
///
/// Implementation:
/// - Connects to D-Bus session bus via UNIX domain socket
/// - Authenticates using EXTERNAL mechanism (UID-based)
/// - Sends notifications via D-Bus binary protocol
/// - Parses METHOD_RETURN messages to get notification IDs

/// Result of ActionInvoked signal - returned when user clicks an action button.
pub const ActionInvokedSignal = struct {
    notification_id: u32,
    action_key: []const u8,

    /// Free the allocated action_key string.
    pub fn deinit(self: *ActionInvokedSignal, allocator: std.mem.Allocator) void {
        allocator.free(self.action_key);
    }
};

pub const LinuxBackend = struct {
    allocator: std.mem.Allocator,
    /// Active D-Bus connection, null if connection failed
    connection: ?net.Stream = null,
    /// Auto-incrementing notification ID counter
    next_id: u32 = 1,
    /// Whether D-Bus connection was successfully established
    available: bool = false,
    /// D-Bus message serial number counter
    serial: u32 = 1,

    /// Initialize Linux backend and connect to D-Bus session bus.
    /// Connection failure is non-fatal; backend will report as unavailable.
    pub fn init(allocator: std.mem.Allocator) !*LinuxBackend {
        const self = try allocator.create(LinuxBackend);
        self.* = LinuxBackend{
            .allocator = allocator,
            .serial = 1,
        };

        // Connect to D-Bus session bus
        self.connectDBus() catch |err| {
            std.debug.print("Failed to connect to D-Bus: {}\n", .{err});
            self.available = false;
            return self;
        };

        self.available = true;
        return self;
    }

    /// Clean up D-Bus connection and free resources.
    pub fn deinit(self: *LinuxBackend) void {
        if (self.connection) |conn| {
            conn.close();
        }
        self.allocator.destroy(self);
    }

    /// Connect to D-Bus session bus via UNIX domain socket.
    /// Parses DBUS_SESSION_BUS_ADDRESS environment variable to find socket path.
    /// Supports both path= (filesystem socket) and abstract= (Linux abstract socket) formats.
    fn connectDBus(self: *LinuxBackend) !void {
        // Get D-Bus session bus address
        const session_addr = try std.process.getEnvVarOwned(
            self.allocator,
            "DBUS_SESSION_BUS_ADDRESS",
        );
        defer self.allocator.free(session_addr);

        // Parse unix:path= or unix:abstract= format
        if (std.mem.startsWith(u8, session_addr, "unix:")) {
            var iter = std.mem.splitScalar(u8, session_addr[5..], ',');
            while (iter.next()) |param| {
                if (std.mem.startsWith(u8, param, "path=")) {
                    const socket_path = param[5..];

                    // Connect to UNIX domain socket
                    const sockfd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
                    var sockfd_owned = true;
                    errdefer if (sockfd_owned) std.posix.close(sockfd);

                    const addr = try net.Address.initUnix(socket_path);
                    try std.posix.connect(sockfd, &addr.any, addr.getOsSockLen());

                    self.connection = net.Stream{ .handle = sockfd };
                    sockfd_owned = false; // self.connection now owns the socket

                    // Authenticate with D-Bus
                    self.authenticateDBus() catch |err| {
                        if (self.connection) |conn| {
                            conn.close();
                        }
                        self.connection = null;
                        return err;
                    };
                    return;
                }
                if (std.mem.startsWith(u8, param, "abstract=")) {
                    // Abstract socket (Linux-specific)
                    const socket_name = param[9..];
                    var buf: [108]u8 = undefined;
                    buf[0] = 0; // Abstract socket marker
                    @memcpy(buf[1..socket_name.len + 1], socket_name);

                    // For abstract sockets, we need to create the socket manually
                    const sockfd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
                    var sockfd_owned = true;
                    errdefer if (sockfd_owned) std.posix.close(sockfd);

                    const addr = try net.Address.initUnix(buf[0..socket_name.len + 1]);
                    try std.posix.connect(sockfd, &addr.any, addr.getOsSockLen());

                    self.connection = net.Stream{ .handle = sockfd };
                    sockfd_owned = false; // self.connection now owns the socket

                    // Authenticate with D-Bus
                    self.authenticateDBus() catch |err| {
                        if (self.connection) |conn| {
                            conn.close();
                        }
                        self.connection = null;
                        return err;
                    };
                    return;
                }
            }
        }

        return error.InvalidDBusAddress;
    }

    /// Authenticate with D-Bus daemon using EXTERNAL mechanism.
    ///
    /// D-Bus authentication protocol:
    /// 1. Send NULL byte (protocol version indicator)
    /// 2. Send "AUTH EXTERNAL <hex-encoded-uid>\r\n"
    /// 3. Wait for "OK <server-guid>\r\n" response
    /// 4. Send "BEGIN\r\n" to start message exchange
    ///
    /// EXTERNAL mechanism uses UNIX credentials (UID) for authentication.
    fn authenticateDBus(self: *LinuxBackend) !void {
        const conn = self.connection orelse return error.NoConnection;

        // Send NULL byte to indicate protocol version
        _ = try conn.write(&[_]u8{0});

        // D-Bus AUTH protocol using EXTERNAL mechanism (UID-based)
        const uid = std.posix.getuid();
        var uid_hex: [32]u8 = undefined;
        const uid_str = try std.fmt.bufPrint(&uid_hex, "{d}", .{uid});

        // Convert UID string to hex (each char to 2 hex digits)
        var hex_buf: [64]u8 = undefined;
        var hex_len: usize = 0;
        for (uid_str) |c| {
            const hex_chars = try std.fmt.bufPrint(hex_buf[hex_len..], "{X:0>2}", .{c});
            hex_len += hex_chars.len;
        }
        const hex_uid = hex_buf[0..hex_len];

        // Send AUTH EXTERNAL <hex-uid>
        var auth_msg: [256]u8 = undefined;
        const auth = try std.fmt.bufPrint(&auth_msg, "AUTH EXTERNAL {s}\r\n", .{hex_uid});
        _ = try conn.write(auth);

        // Read response (should be "OK <server-guid>")
        var response: [512]u8 = undefined;
        const n = try conn.read(&response);
        if (n == 0 or !std.mem.startsWith(u8, response[0..n], "OK ")) {
            return error.AuthFailed;
        }

        // Send BEGIN
        _ = try conn.write("BEGIN\r\n");

        // After authentication, we must call Hello() to get a unique name
        try self.sendHello();
    }

    /// Send GetCapabilities() method call to notification daemon.
    /// Returns the capabilities supported by the daemon.
    fn sendGetCapabilitiesMethodCall(self: *LinuxBackend, serial: u32) !void {
        const conn = self.connection orelse return error.NoConnection;

        var msg: std.ArrayList(u8) = .{};
        try msg.ensureTotalCapacity(self.allocator, 512);
        defer msg.deinit(self.allocator);

        // Endianness
        try msg.append(self.allocator, 'l');
        // Message type (METHOD_CALL)
        try msg.append(self.allocator, 1);
        // Flags
        try msg.append(self.allocator, 0);
        // Protocol version
        try msg.append(self.allocator, 1);

        // Body length (no parameters)
        try msg.writer(self.allocator).writeInt(u32, 0, .little);

        // Serial
        try msg.writer(self.allocator).writeInt(u32, serial, .little);

        // Build header fields
        var header_fields: std.ArrayList(u8) = .{};
        try header_fields.ensureTotalCapacity(self.allocator, 256);
        defer header_fields.deinit(self.allocator);

        // PATH
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 1);
        try appendSignature(&header_fields, self.allocator, "o");
        try appendObjectPath(&header_fields, self.allocator, "/org/freedesktop/Notifications");

        // INTERFACE
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 2);
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "org.freedesktop.Notifications");

        // MEMBER
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 3);
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "GetCapabilities");

        // DESTINATION
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 6);
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "org.freedesktop.Notifications");

        // Write header fields
        try msg.writer(self.allocator).writeInt(u32, @intCast(header_fields.items.len), .little);
        try msg.appendSlice(self.allocator, header_fields.items);

        // Pad to 8-byte boundary (no body)
        while (msg.items.len % 8 != 0) {
            try msg.append(self.allocator, 0);
        }

        // Send message
        _ = try conn.write(msg.items);
    }

    /// Send Hello() message to D-Bus to establish connection and get unique name.
    /// This must be called after authentication and before any other D-Bus method calls.
    fn sendHello(self: *LinuxBackend) !void {
        const conn = self.connection orelse return error.NoConnection;

        var msg: std.ArrayList(u8) = .{};
        try msg.ensureTotalCapacity(self.allocator, 512);
        defer msg.deinit(self.allocator);

        // Build Hello() METHOD_CALL message
        const serial = self.serial;
        self.serial += 1;

        // Endianness
        try msg.append(self.allocator, 'l');
        // Message type (METHOD_CALL)
        try msg.append(self.allocator, 1);
        // Flags
        try msg.append(self.allocator, 0);
        // Protocol version
        try msg.append(self.allocator, 1);

        // Body length (Hello has no parameters)
        try msg.writer(self.allocator).writeInt(u32, 0, .little);

        // Serial
        try msg.writer(self.allocator).writeInt(u32, serial, .little);

        // Build header fields
        var header_fields: std.ArrayList(u8) = .{};
        try header_fields.ensureTotalCapacity(self.allocator, 256);
        defer header_fields.deinit(self.allocator);

        // PATH
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 1);
        try appendSignature(&header_fields, self.allocator, "o");
        try appendObjectPath(&header_fields, self.allocator, "/org/freedesktop/DBus");

        // INTERFACE
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 2);
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "org.freedesktop.DBus");

        // MEMBER
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 3);
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "Hello");

        // DESTINATION
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 6);
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "org.freedesktop.DBus");

        // Write header fields
        try msg.writer(self.allocator).writeInt(u32, @intCast(header_fields.items.len), .little);
        try msg.appendSlice(self.allocator, header_fields.items);

        // Pad to 8-byte boundary (no body for Hello)
        while (msg.items.len % 8 != 0) {
            try msg.append(self.allocator, 0);
        }

        // Send message
        _ = try conn.write(msg.items);

        // Read and discard reply (we don't need the unique name)
        _ = try self.readNotifyReply();
    }

    /// Send notification via D-Bus to org.freedesktop.Notifications.Notify.
    /// Returns notification ID assigned by the notification daemon.
    pub fn send(self: *LinuxBackend, notif: notification.Notification) !u32 {
        if (!self.available or self.connection == null) {
            return errors.ZNotifyError.NotificationFailed;
        }

        // Send D-Bus method call to org.freedesktop.Notifications.Notify
        const msg_serial = self.serial;
        self.serial += 1;

        try self.sendNotifyMethodCall(notif, msg_serial);

        // Read response
        const notif_id = try self.readNotifyReply();
        return notif_id;
    }

    /// Marshal and send D-Bus METHOD_CALL message for Notify().
    ///
    /// D-Bus binary protocol message structure:
    /// - Header: endianness, type, flags, version, body_length, serial
    /// - Header fields: PATH, INTERFACE, MEMBER, DESTINATION, SIGNATURE
    /// - 8-byte alignment padding
    /// - Body: app_name, replaces_id, icon, title, message, actions, hints, timeout
    ///
    /// Notify method signature: susssasa{sv}i
    /// - s: app_name (string)
    /// - u: replaces_id (uint32)
    /// - s: app_icon (string)
    /// - s: summary/title (string)
    /// - s: body/message (string)
    /// - as: actions (array of strings)
    /// - a{sv}: hints (dict of string to variant)
    /// - i: expire_timeout (int32)
    fn sendNotifyMethodCall(self: *LinuxBackend, notif: notification.Notification, serial: u32) !void {
        const conn = self.connection orelse return error.NoConnection;

        // Build D-Bus message using binary protocol

        var msg: std.ArrayList(u8) = .{};
        try msg.ensureTotalCapacity(self.allocator, 1024);
        defer msg.deinit(self.allocator);

        // Endianness ('l' for little-endian)
        try msg.append(self.allocator, 'l');

        // Message type (1 = METHOD_CALL)
        try msg.append(self.allocator, 1);

        // Flags (0 = no flags)
        try msg.append(self.allocator, 0);

        // Protocol version (1)
        try msg.append(self.allocator, 1);

        // Reserve space for body length (4 bytes) - will fill later
        const body_len_pos = msg.items.len;
        try msg.appendSlice(self.allocator, &[_]u8{0, 0, 0, 0});

        // Serial number
        try msg.writer(self.allocator).writeInt(u32, serial, .little);

        // Build header fields array first to calculate length
        var header_fields: std.ArrayList(u8) = .{};
        try header_fields.ensureTotalCapacity(self.allocator, 512);
        defer header_fields.deinit(self.allocator);

        // Field 1: PATH (object path)
        // Each header field struct must be 8-byte aligned
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 1); // OBJECT_PATH
        try appendSignature(&header_fields, self.allocator, "o");
        try appendObjectPath(&header_fields, self.allocator, "/org/freedesktop/Notifications");

        // Field 2: INTERFACE
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 2); // INTERFACE
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "org.freedesktop.Notifications");

        // Field 3: MEMBER (method name)
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 3); // MEMBER
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "Notify");

        // Field 6: DESTINATION
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 6); // DESTINATION
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "org.freedesktop.Notifications");

        // Field 8: SIGNATURE
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 8); // SIGNATURE
        try appendSignature(&header_fields, self.allocator, "g");
        try appendSignature(&header_fields, self.allocator, "susssasa{sv}i");

        // Write header fields array length
        try msg.writer(self.allocator).writeInt(u32, @intCast(header_fields.items.len), .little);
        try msg.appendSlice(self.allocator, header_fields.items);

        // Pad to 8-byte alignment for body
        while (msg.items.len % 8 != 0) {
            try msg.append(self.allocator, 0);
        }

        const body_start = msg.items.len;

        // Build message body: Notify(susssasa{sv}i)
        // s: app_name (strings need 4-byte alignment for their length field)
        while (msg.items.len % 4 != 0) {
            try msg.append(self.allocator, 0);
        }
        try appendString(&msg, self.allocator, notif.app_name);

        // u: replaces_id (u32 needs 4-byte alignment)
        while (msg.items.len % 4 != 0) {
            try msg.append(self.allocator, 0);
        }
        try msg.writer(self.allocator).writeInt(u32, notif.replace_id orelse 0, .little);

        // s: app_icon
        while (msg.items.len % 4 != 0) {
            try msg.append(self.allocator, 0);
        }
        const icon_str = switch (notif.icon) {
            .none => "",
            .builtin => |b| @tagName(b),
            .file_path => |p| p,
            .url => |u| u,
        };
        try appendString(&msg, self.allocator, icon_str);

        // s: summary (title)
        while (msg.items.len % 4 != 0) {
            try msg.append(self.allocator, 0);
        }
        try appendString(&msg, self.allocator, notif.title);

        // s: body (message)
        while (msg.items.len % 4 != 0) {
            try msg.append(self.allocator, 0);
        }
        try appendString(&msg, self.allocator, notif.message);

        // as: actions array (format: ["id1", "label1", "id2", "label2", ...])
        // Build actions array with string elements
        var actions_array: std.ArrayList(u8) = .{};
        try actions_array.ensureTotalCapacity(self.allocator, 128);
        defer actions_array.deinit(self.allocator);

        for (notif.actions) |action| {
            // Each string needs 4-byte alignment
            while (actions_array.items.len % 4 != 0) {
                try actions_array.append(self.allocator, 0);
            }
            // Add action ID
            try appendString(&actions_array, self.allocator, action.id);

            // Align for next string
            while (actions_array.items.len % 4 != 0) {
                try actions_array.append(self.allocator, 0);
            }
            // Add action label
            try appendString(&actions_array, self.allocator, action.label);
        }

        // Write actions array: 4-byte aligned length + array contents
        while (msg.items.len % 4 != 0) {
            try msg.append(self.allocator, 0);
        }
        try msg.writer(self.allocator).writeInt(u32, @intCast(actions_array.items.len), .little);
        if (actions_array.items.len > 0) {
            try msg.appendSlice(self.allocator, actions_array.items);
        }

        // a{sv}: hints (dict with urgency)
        // Build hints dictionary with urgency level
        var hints: std.ArrayList(u8) = .{};
        try hints.ensureTotalCapacity(self.allocator, 64);
        defer hints.deinit(self.allocator);

        // Map urgency to D-Bus notification spec values: 0=low, 1=normal, 2=critical
        const urgency_value: u8 = switch (notif.urgency) {
            .low => 0,
            .normal => 1,
            .critical => 2,
        };
        try appendHintEntry(&hints, self.allocator, "urgency", urgency_value);

        // Write hints array: 4-byte aligned length + padding + array contents
        while (msg.items.len % 4 != 0) {
            try msg.append(self.allocator, 0);
        }
        try msg.writer(self.allocator).writeInt(u32, @intCast(hints.items.len), .little);

        // After array length, align to 8 bytes for dict entries (if array is non-empty)
        if (hints.items.len > 0) {
            while (msg.items.len % 8 != 0) {
                try msg.append(self.allocator, 0);
            }
        }
        try msg.appendSlice(self.allocator, hints.items);

        // i: expire_timeout
        const timeout: i32 = if (notif.timeout_ms) |t| @intCast(t) else -1;
        try msg.writer(self.allocator).writeInt(i32, timeout, .little);

        // Fill in body length
        const body_len: u32 = @intCast(msg.items.len - body_start);
        std.mem.writeInt(u32, msg.items[body_len_pos..][0..4], body_len, .little);

        // Send the message
        _ = try conn.write(msg.items);
    }

    /// Marshal and send D-Bus METHOD_CALL message for CloseNotification().
    ///
    /// CloseNotification method signature: u
    /// - u: notification_id (uint32)
    ///
    /// Does not wait for a reply since we don't need confirmation.
    fn sendCloseNotificationMethodCall(self: *LinuxBackend, id: u32, serial: u32) !void {
        const conn = self.connection orelse return error.NoConnection;

        var msg: std.ArrayList(u8) = .{};
        try msg.ensureTotalCapacity(self.allocator, 512);
        defer msg.deinit(self.allocator);

        // Endianness ('l' for little-endian)
        try msg.append(self.allocator, 'l');

        // Message type (1 = METHOD_CALL)
        try msg.append(self.allocator, 1);

        // Flags (0 = none, or 1 = no reply expected)
        try msg.append(self.allocator, 1); // NO_REPLY_EXPECTED

        // Protocol version (1)
        try msg.append(self.allocator, 1);

        // Body length (placeholder, will be filled later)
        const body_len_pos = msg.items.len;
        try msg.writer(self.allocator).writeInt(u32, 0, .little);

        // Serial number
        try msg.writer(self.allocator).writeInt(u32, serial, .little);

        // Header fields array length (placeholder)
        const header_fields_start = msg.items.len;
        try msg.writer(self.allocator).writeInt(u32, 0, .little);

        // Header field 1: PATH
        try msg.append(self.allocator, 1); // HEADER_FIELD_PATH
        try appendSignature(&msg, self.allocator, "o");
        try appendObjectPath(&msg, self.allocator, "/org/freedesktop/Notifications");

        // Header field 2: INTERFACE
        try msg.append(self.allocator, 2); // HEADER_FIELD_INTERFACE
        try appendSignature(&msg, self.allocator, "s");
        try appendString(&msg, self.allocator, "org.freedesktop.Notifications");

        // Header field 3: MEMBER
        try msg.append(self.allocator, 3); // HEADER_FIELD_MEMBER
        try appendSignature(&msg, self.allocator, "s");
        try appendString(&msg, self.allocator, "CloseNotification");

        // Header field 6: DESTINATION
        try msg.append(self.allocator, 6); // HEADER_FIELD_DESTINATION
        try appendSignature(&msg, self.allocator, "s");
        try appendString(&msg, self.allocator, "org.freedesktop.Notifications");

        // Header field 8: SIGNATURE
        try msg.append(self.allocator, 8); // HEADER_FIELD_SIGNATURE
        try appendSignature(&msg, self.allocator, "u"); // Single uint32 parameter

        // Update header fields length
        const header_fields_len: u32 = @intCast(msg.items.len - header_fields_start - 4);
        std.mem.writeInt(u32, msg.items[header_fields_start..][0..4], header_fields_len, .little);

        // Align to 8-byte boundary for body
        const current_len = msg.items.len;
        const padding = (8 - (current_len % 8)) % 8;
        try msg.appendNTimes(self.allocator, 0, padding);

        // Body: notification ID (uint32)
        const body_start = msg.items.len;
        try msg.writer(self.allocator).writeInt(u32, id, .little);

        // Update body length in header
        const body_len: u32 = @intCast(msg.items.len - body_start);
        std.mem.writeInt(u32, msg.items[body_len_pos..][0..4], body_len, .little);

        // Send the message (no reply expected)
        _ = try conn.write(msg.items);
    }

    /// Helper to read exact number of bytes from connection.
    /// Loops until all bytes are read or connection is closed.
    fn readExact(conn: net.Stream, buffer: []u8) !void {
        var total_read: usize = 0;
        while (total_read < buffer.len) {
            const n = try conn.read(buffer[total_read..]);
            if (n == 0) return error.ConnectionClosed;
            total_read += n;
        }
    }

    /// Read and parse D-Bus METHOD_RETURN message to extract notification ID.
    ///
    /// D-Bus reply message structure:
    /// - Header (16 bytes): endianness, type, flags, version, body_len, serial, header_fields_len
    /// - Header fields (variable): reply metadata
    /// - Padding to 8-byte boundary
    /// - Body (4 bytes): uint32 notification ID
    ///
    /// Returns the notification ID assigned by the daemon.
    fn readNotifyReply(self: *LinuxBackend) !u32 {
        const conn = self.connection orelse return error.NoConnection;

        // Loop to handle multiple messages (signals, etc.) until we get METHOD_RETURN
        while (true) {
            var header: [16]u8 = undefined;
            try readExact(conn, &header);

            // Parse header
            const endian = header[0];
            if (endian != 'l') return error.UnsupportedEndianness;

            const msg_type = header[1];
            const body_len = std.mem.readInt(u32, header[4..8], .little);
            const header_fields_len = std.mem.readInt(u32, header[12..16], .little);

            // If this is not a METHOD_RETURN, skip the entire message
            if (msg_type != 2) { // 2 = METHOD_RETURN
                // Skip header fields
                var skip_buf: [1024]u8 = undefined;
                var remaining = header_fields_len;
                while (remaining > 0) {
                    const to_read = @min(remaining, skip_buf.len);
                    try readExact(conn, skip_buf[0..to_read]);
                    remaining -= to_read;
                }

                // Skip padding to 8-byte boundary
                const total_header_len = 16 + header_fields_len;
                const padding = (8 - (total_header_len % 8)) % 8;
                if (padding > 0) {
                    try readExact(conn, skip_buf[0..padding]);
                }

                // Skip body
                remaining = body_len;
                while (remaining > 0) {
                    const to_read = @min(remaining, skip_buf.len);
                    try readExact(conn, skip_buf[0..to_read]);
                    remaining -= to_read;
                }

                // Continue to next message
                continue;
            }

            // This is a METHOD_RETURN, process it
            // Skip header fields
            var skip_buf: [1024]u8 = undefined;
            var remaining = header_fields_len;
            while (remaining > 0) {
                const to_read = @min(remaining, skip_buf.len);
                try readExact(conn, skip_buf[0..to_read]);
                remaining -= to_read;
            }

            // Skip padding to 8-byte boundary
            const total_header_len = 16 + header_fields_len;
            const padding = (8 - (total_header_len % 8)) % 8;
            if (padding > 0) {
                try readExact(conn, skip_buf[0..padding]);
            }

            // Read body (should be UINT32)
            if (body_len < 4) return error.InvalidReplyBody;

            var body: [4]u8 = undefined;
            try readExact(conn, &body);

            const notif_id = std.mem.readInt(u32, &body, .little);

            // Consume any remaining body
            if (body_len > 4) {
                remaining = body_len - 4;
                while (remaining > 0) {
                    const to_read = @min(remaining, skip_buf.len);
                    try readExact(conn, skip_buf[0..to_read]);
                    remaining -= to_read;
                }
            }

            return notif_id;
        }
    }

    /// Read and parse D-Bus METHOD_RETURN message to extract capabilities array.
    ///
    /// D-Bus reply message structure:
    /// - Header (16 bytes): endianness, type, flags, version, body_len, serial, header_fields_len
    /// - Header fields (variable): reply metadata
    /// - Padding to 8-byte boundary
    /// - Body: ARRAY of STRING (signature "as")
    ///
    /// Returns comma-separated string of capabilities. Caller owns memory.
    fn readCapabilitiesReply(self: *LinuxBackend, allocator: std.mem.Allocator) ![]const u8 {
        const conn = self.connection orelse return error.NoConnection;

        // Loop to handle multiple messages (signals, etc.) until we get METHOD_RETURN
        while (true) {
            var header: [16]u8 = undefined;
            try readExact(conn, &header);

            // Parse header
            const endian = header[0];
            if (endian != 'l') return error.UnsupportedEndianness;

            const msg_type = header[1];
            const body_len = std.mem.readInt(u32, header[4..8], .little);
            const header_fields_len = std.mem.readInt(u32, header[12..16], .little);

            // If this is not a METHOD_RETURN, skip the entire message
            if (msg_type != 2) { // 2 = METHOD_RETURN
                // Skip header fields
                var skip_buf: [1024]u8 = undefined;
                var remaining = header_fields_len;
                while (remaining > 0) {
                    const to_read = @min(remaining, skip_buf.len);
                    try readExact(conn, skip_buf[0..to_read]);
                    remaining -= to_read;
                }

                // Skip padding to 8-byte boundary
                const total_header_len = 16 + header_fields_len;
                const padding = (8 - (total_header_len % 8)) % 8;
                if (padding > 0) {
                    try readExact(conn, skip_buf[0..padding]);
                }

                // Skip body
                remaining = body_len;
                while (remaining > 0) {
                    const to_read = @min(remaining, skip_buf.len);
                    try readExact(conn, skip_buf[0..to_read]);
                    remaining -= to_read;
                }
                continue;
            }

            // Skip header fields (we don't need them)
            var skip_buf: [1024]u8 = undefined;
            var remaining = header_fields_len;
            while (remaining > 0) {
                const to_read = @min(remaining, skip_buf.len);
                try readExact(conn, skip_buf[0..to_read]);
                remaining -= to_read;
            }

            // Skip padding to 8-byte boundary
            const total_header_len = 16 + header_fields_len;
            const padding = (8 - (total_header_len % 8)) % 8;
            if (padding > 0) {
                try readExact(conn, skip_buf[0..padding]);
            }

            // Read body - array of strings (signature "as")
            if (body_len < 4) return error.InvalidReplyBody;

            // Read all body bytes into buffer
            const body = try allocator.alloc(u8, body_len);
            defer allocator.free(body);
            try readExact(conn, body);

            // Parse array of strings
            // First 4 bytes: array length (total bytes in array, not count)
            const array_len = std.mem.readInt(u32, body[0..4], .little);
            if (array_len > body_len - 4) return error.InvalidReplyBody;

            // Build comma-separated string
            var result: std.ArrayList(u8) = .{};
            defer result.deinit(allocator);

            var array_offset: usize = 0; // Track position within the array data
            const array_data_start: usize = 4; // Array data starts after length field
            var first = true;

            while (array_offset < array_len) {
                // Calculate absolute position in body buffer
                const body_offset = array_data_start + array_offset;

                // Strings in arrays need 4-byte alignment - check alignment relative to message start
                const alignment_padding = (4 - (body_offset % 4)) % 4;
                array_offset += alignment_padding;

                // Each string: 4-byte length + string bytes + NUL
                const final_offset = array_data_start + array_offset;
                if (final_offset + 4 > body.len) break;

                const str_len = std.mem.readInt(u32, body[final_offset..][0..4], .little);
                array_offset += 4;

                const str_start = array_data_start + array_offset;
                if (str_start + str_len + 1 > body.len) break;

                const str = body[str_start .. str_start + str_len];
                array_offset += str_len + 1; // +1 for NUL terminator

                // Add comma separator (except for first item)
                if (!first) {
                    try result.append(allocator, ',');
                }
                first = false;

                // Add capability string
                try result.appendSlice(allocator, str);
            }

            return result.toOwnedSlice(allocator);
        }
    }

    /// Close/dismiss a notification by ID via D-Bus CloseNotification method.
    /// Sends a METHOD_CALL to org.freedesktop.Notifications.CloseNotification.
    pub fn close(self: *LinuxBackend, id: u32) !void {
        if (!self.available or self.connection == null) {
            return errors.ZNotifyError.NotificationFailed;
        }

        const msg_serial = self.serial;
        self.serial += 1;

        try self.sendCloseNotificationMethodCall(id, msg_serial);
    }

    /// Return comma-separated list of supported capabilities.
    /// Caller owns returned memory and must free it.
    ///
    /// Capabilities reported:
    /// - body: Notification body text
    /// - body-markup: HTML markup in body
    /// - actions: Action buttons
    /// - urgency: Urgency levels
    /// - icon-static: Static icons
    /// - persistence: Persistent notifications
    pub fn getCapabilities(self: *LinuxBackend, allocator: std.mem.Allocator) ![]const u8 {
        if (!self.available or self.connection == null) {
            return allocator.dupe(u8, "");
        }

        // Send GetCapabilities method call
        const msg_serial = self.serial;
        self.serial += 1;
        try self.sendGetCapabilitiesMethodCall(msg_serial);

        // Read and parse response
        const caps_list = try self.readCapabilitiesReply(allocator);
        return caps_list;
    }

    /// Check if a specific capability is supported by the notification daemon.
    /// Queries the daemon and checks if the capability name appears in the list.
    pub fn hasCapability(self: *LinuxBackend, allocator: std.mem.Allocator, capability: []const u8) !bool {
        const caps = try self.getCapabilities(allocator);
        defer allocator.free(caps);
        return std.mem.indexOf(u8, caps, capability) != null;
    }

    /// Check if action buttons are supported.
    pub fn supportsActions(self: *LinuxBackend, allocator: std.mem.Allocator) !bool {
        return self.hasCapability(allocator, "actions");
    }

    /// Check if static icons are supported.
    pub fn supportsIcons(self: *LinuxBackend, allocator: std.mem.Allocator) !bool {
        return self.hasCapability(allocator, "icon-static");
    }

    /// Check if body markup (HTML) is supported.
    pub fn supportsBodyMarkup(self: *LinuxBackend, allocator: std.mem.Allocator) !bool {
        return self.hasCapability(allocator, "body-markup");
    }

    /// Check if D-Bus connection was successfully established.
    pub fn isAvailable(self: *LinuxBackend) bool {
        return self.available;
    }

    /// Subscribe to ActionInvoked signals from the notification daemon.
    /// Must be called before waitForActionInvokedSignal().
    pub fn addMatchRule(self: *LinuxBackend) !void {
        const conn = self.connection orelse return error.NoConnection;

        var msg: std.ArrayList(u8) = .{};
        try msg.ensureTotalCapacity(self.allocator, 512);
        defer msg.deinit(self.allocator);

        // Build AddMatch METHOD_CALL message
        const serial = self.serial;
        self.serial += 1;

        // Endianness
        try msg.append(self.allocator, 'l');
        // Message type (METHOD_CALL)
        try msg.append(self.allocator, 1);
        // Flags
        try msg.append(self.allocator, 0);
        // Protocol version
        try msg.append(self.allocator, 1);

        // Match rule string
        const match_rule = "type='signal',interface='org.freedesktop.Notifications',member='ActionInvoked'";

        // Body length (string: 4 bytes length + string + NUL)
        const body_len: u32 = @intCast(4 + match_rule.len + 1);
        try msg.writer(self.allocator).writeInt(u32, body_len, .little);

        // Serial
        try msg.writer(self.allocator).writeInt(u32, serial, .little);

        // Build header fields
        var header_fields: std.ArrayList(u8) = .{};
        try header_fields.ensureTotalCapacity(self.allocator, 256);
        defer header_fields.deinit(self.allocator);

        // PATH
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 1);
        try appendSignature(&header_fields, self.allocator, "o");
        try appendObjectPath(&header_fields, self.allocator, "/org/freedesktop/DBus");

        // INTERFACE
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 2);
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "org.freedesktop.DBus");

        // MEMBER
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 3);
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "AddMatch");

        // DESTINATION
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 6);
        try appendSignature(&header_fields, self.allocator, "s");
        try appendString(&header_fields, self.allocator, "org.freedesktop.DBus");

        // SIGNATURE (body signature is "s" - one string argument)
        while (header_fields.items.len % 8 != 0) {
            try header_fields.append(self.allocator, 0);
        }
        try header_fields.append(self.allocator, 8);
        try appendSignature(&header_fields, self.allocator, "g"); // signature field type is 'g'
        try appendSignature(&header_fields, self.allocator, "s"); // body signature is 's'

        // Write header fields
        try msg.writer(self.allocator).writeInt(u32, @intCast(header_fields.items.len), .little);
        try msg.appendSlice(self.allocator, header_fields.items);

        // Pad to 8-byte boundary before body
        while (msg.items.len % 8 != 0) {
            try msg.append(self.allocator, 0);
        }

        // Body: match rule string
        try appendString(&msg, self.allocator, match_rule);

        // Send message (don't wait for reply - it will be read in the message loop)
        _ = try conn.write(msg.items);
    }

    /// Wait for and parse ActionInvoked signal from notification daemon.
    /// Returns notification ID and action key when an action button is clicked.
    /// Blocks until a signal is received or timeout occurs.
    /// Timeout of 0 means wait indefinitely.
    pub fn waitForActionInvokedSignal(
        self: *LinuxBackend,
        allocator: std.mem.Allocator,
        target_notif_id: u32,
        timeout_ms: u32,
    ) !ActionInvokedSignal {
        const conn = self.connection orelse return error.NoConnection;

        // Convert timeout: 0 = infinite (-1 for poll), >0 = milliseconds
        const poll_timeout: i32 = if (timeout_ms == 0) -1 else @intCast(timeout_ms);

        // Loop waiting for ActionInvoked signal
        while (true) {
            // Check if data is available with timeout
            var poll_fd = [_]std.posix.pollfd{.{
                .fd = conn.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            }};

            const ready = try std.posix.poll(&poll_fd, poll_timeout);
            if (ready == 0) {
                return error.Timeout;
            }

            var header: [16]u8 = undefined;
            try readExact(conn, &header);

            // Parse header
            const endian = header[0];
            if (endian != 'l') return error.UnsupportedEndianness;

            const msg_type = header[1];
            const body_len = std.mem.readInt(u32, header[4..8], .little);
            const header_fields_len = std.mem.readInt(u32, header[12..16], .little);


            // If this is not a SIGNAL (type 4), skip it
            if (msg_type != 4) {
                // Skip header fields
                var skip_buf: [1024]u8 = undefined;
                var remaining = header_fields_len;
                while (remaining > 0) {
                    const to_read = @min(remaining, skip_buf.len);
                    try readExact(conn, skip_buf[0..to_read]);
                    remaining -= to_read;
                }

                // Skip padding
                const total_header_len = 16 + header_fields_len;
                const padding = (8 - (total_header_len % 8)) % 8;
                if (padding > 0) {
                    try readExact(conn, skip_buf[0..padding]);
                }

                // Skip body
                remaining = body_len;
                while (remaining > 0) {
                    const to_read = @min(remaining, skip_buf.len);
                    try readExact(conn, skip_buf[0..to_read]);
                    remaining -= to_read;
                }

                continue;
            }

            // This is a SIGNAL - parse header fields to check if it's ActionInvoked

            // Read header fields to check interface and member
            var header_fields_buf = try allocator.alloc(u8, header_fields_len);
            defer allocator.free(header_fields_buf);
            try readExact(conn, header_fields_buf);

            // Parse header fields to find INTERFACE (2) and MEMBER (3)
            var interface: ?[]const u8 = null;
            var member: ?[]const u8 = null;
            var offset: usize = 0;

            while (offset < header_fields_len) {

                if (offset + 8 > header_fields_len) {
                    break;
                }

                // Align to 8-byte boundary
                offset = std.mem.alignForward(usize, offset, 8);

                if (offset >= header_fields_len) {
                    break;
                }

                const field_code = header_fields_buf[offset];
                offset += 1;

                // Field signature (1 byte type code for our simple cases)
                if (offset >= header_fields_len) break;
                const sig_len = header_fields_buf[offset];
                offset += 1;
                offset += sig_len + 1; // Skip signature + NUL

                // Field 8 (SIGNATURE) uses 1-byte length, others use 4-byte length
                const str_len: u32 = if (field_code == 8) blk: {
                    // Signature field: 1-byte length
                    if (offset >= header_fields_len) break;
                    const len = header_fields_buf[offset];
                    offset += 1;
                    break :blk len;
                } else blk: {
                    // Other fields: 4-byte length with alignment
                    offset = std.mem.alignForward(usize, offset, 4);
                    if (offset + 4 > header_fields_len) break;
                    const len = std.mem.readInt(u32, header_fields_buf[offset..][0..4], .little);
                    offset += 4;
                    break :blk len;
                };

                if (offset + str_len >= header_fields_len) {
                    break;
                }
                const str_value = header_fields_buf[offset .. offset + str_len];
                offset += str_len + 1; // +1 for NUL terminator

                if (field_code == 2) { // INTERFACE
                    interface = str_value;
                } else if (field_code == 3) { // MEMBER
                    member = str_value;
                }
            }

            // Check if this is the ActionInvoked signal we're looking for
            const is_action_invoked = blk: {
                if (interface == null or member == null) break :blk false;
                if (!std.mem.eql(u8, interface.?, "org.freedesktop.Notifications")) break :blk false;
                if (!std.mem.eql(u8, member.?, "ActionInvoked")) break :blk false;
                break :blk true;
            };

            if (!is_action_invoked) {
                // Skip padding to 8-byte boundary
                const total_header_len = 16 + header_fields_len;
                const padding = (8 - (total_header_len % 8)) % 8;
                if (padding > 0) {
                    var pad_buf: [8]u8 = undefined;
                    try readExact(conn, pad_buf[0..padding]);
                }

                // Skip body
                var skip_buf: [1024]u8 = undefined;
                var remaining = body_len;
                while (remaining > 0) {
                    const to_read = @min(remaining, skip_buf.len);
                    const n = try conn.read(skip_buf[0..to_read]);
                    if (n == 0) return error.ConnectionClosed;
                    remaining -= @intCast(n);
                }
                continue;
            }

            // Skip padding to 8-byte boundary
            const total_header_len = 16 + header_fields_len;
            const padding = (8 - (total_header_len % 8)) % 8;
            if (padding > 0) {
                var pad_buf: [8]u8 = undefined;
                try readExact(conn, pad_buf[0..padding]);
            }

            // Read body: uint32 notification_id + string action_key
            // Body format: uint32 (4 bytes) + uint32 string_len + string + NUL
            if (body_len < 8) return error.InvalidSignalBody;

            // Read notification ID (uint32)
            var id_buf: [4]u8 = undefined;
            try readExact(conn, &id_buf);
            const notif_id = std.mem.readInt(u32, &id_buf, .little);

            // Read action key string length
            var str_len_buf: [4]u8 = undefined;
            try readExact(conn, &str_len_buf);
            const str_len = std.mem.readInt(u32, &str_len_buf, .little);

            // Read action key string
            const action_key = try allocator.alloc(u8, str_len);
            errdefer allocator.free(action_key);
            try readExact(conn, @constCast(action_key));

            // Read NUL terminator
            var nul: [1]u8 = undefined;
            try readExact(conn, &nul);

            // If this signal is for our notification, return it
            if (notif_id == target_notif_id) {
                return ActionInvokedSignal{
                    .notification_id = notif_id,
                    .action_key = action_key,
                };
            }

            // Wrong notification, free string and continue
            allocator.free(action_key);
        }
    }

    /// VTable implementation for Linux backend.
    pub const vtable = backend.Backend.VTable{
        .init = @ptrCast(&LinuxBackend.init),
        .deinit = @ptrCast(&LinuxBackend.deinit),
        .send = @ptrCast(&LinuxBackend.send),
        .close = @ptrCast(&LinuxBackend.close),
        .getCapabilities = @ptrCast(&LinuxBackend.getCapabilities),
        .isAvailable = @ptrCast(&LinuxBackend.isAvailable),
    };
};

// D-Bus message marshalling helper functions

/// Append D-Bus signature to message buffer.
/// Format: length byte + signature string + NUL terminator
fn appendSignature(list: *std.ArrayList(u8), allocator: std.mem.Allocator, sig: []const u8) !void {
    try list.append(allocator, @intCast(sig.len));
    try list.appendSlice(allocator, sig);
    try list.append(allocator, 0); // NUL terminator
}

/// Append D-Bus string to message buffer.
/// Format: uint32 length + string bytes + NUL terminator
fn appendString(list: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    try list.writer(allocator).writeInt(u32, @intCast(str.len), .little);
    try list.appendSlice(allocator, str);
    try list.append(allocator, 0); // NUL terminator
}

/// Append D-Bus variant containing a byte value to message buffer.
/// Format: signature length (1 byte) + signature ('y') + NUL + value
/// Note: Signature string does NOT include length byte, just the type char + NUL
fn appendVariantByte(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u8) !void {
    try list.append(allocator, 1); // signature string length (just 'y', not including NUL)
    try list.append(allocator, 'y'); // byte type signature
    try list.append(allocator, 0); // NUL terminator for signature
    try list.append(allocator, value); // actual byte value
}

/// Append D-Bus dict entry {sv} to hints array.
/// Format: dict entry with string key and variant value
/// Note: Caller must ensure 8-byte alignment before calling this
fn appendHintEntry(list: *std.ArrayList(u8), allocator: std.mem.Allocator, key: []const u8, value: u8) !void {
    // String key - already includes 4-byte length prefix in appendString
    try appendString(list, allocator, key);

    // Variant value - signature is 1-byte aligned, value follows
    try appendVariantByte(list, allocator, value);
}

/// Append D-Bus object path to message buffer.
/// Object paths must start with '/' and contain only valid characters.
/// Format: same as string (uint32 length + path + NUL)
fn appendObjectPath(list: *std.ArrayList(u8), allocator: std.mem.Allocator, path: []const u8) !void {
    try list.writer(allocator).writeInt(u32, @intCast(path.len), .little);
    try list.appendSlice(allocator, path);
    try list.append(allocator, 0); // NUL terminator
}

/// Create and initialize Linux D-Bus notification backend.
/// Connects to D-Bus session bus and returns a Backend interface.
/// Connection failure is non-fatal; backend will report as unavailable.
pub fn createBackend(allocator: std.mem.Allocator) !backend.Backend {
    const linux_backend = try LinuxBackend.init(allocator);
    return backend.Backend{
        .ptr = linux_backend,
        .vtable = &LinuxBackend.vtable,
    };
}
