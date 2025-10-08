const std = @import("std");
const notification = @import("../notification.zig");
const errors = @import("../errors.zig");
const backend = @import("backend.zig");
const windows = std.os.windows;

/// Windows notification backend using WinRT Toast API.
///
/// Implementation:
/// - Windows 10+: WinRT Toast Notifications API via Windows.UI.Notifications
/// - COM initialization for WinRT interop
/// - XML-based toast template construction
/// - Toast notification display and management
///
/// Features:
/// - Toast notifications with title, body, and icons
/// - Notification history via Action Center
/// - Urgency mapping to audio/priority
/// - Automatic notification ID tracking
pub const WindowsBackend = struct {
    allocator: std.mem.Allocator,
    /// Next notification ID to assign
    next_id: u32 = 1,
    /// Whether COM was successfully initialized
    com_initialized: bool = false,
    /// Whether backend is available
    available: bool = false,

    /// Initialize Windows backend and COM library.
    /// Checks Windows version and initializes COM for WinRT.
    pub fn init(allocator: std.mem.Allocator) !*WindowsBackend {
        const self = try allocator.create(WindowsBackend);
        self.* = WindowsBackend{
            .allocator = allocator,
            .next_id = 1,
            .com_initialized = false,
            .available = false,
        };

        // Initialize COM for apartment-threaded access
        self.initializeCOM() catch {
            return self;
        };

        // Create Start Menu shortcut with AppUserModelID (required for unpackaged apps)
        self.ensureShortcutExists() catch {
            return self;
        };

        self.available = true;
        return self;
    }

    /// Our Application User Model ID for Windows notifications
    const AUMID = "com.znotify.app";

    // COM GUIDs and interfaces for shortcut creation
    const CLSID_ShellLink = windows.GUID.parse("{00021401-0000-0000-C000-000000000046}");
    const IID_IShellLinkW = windows.GUID.parse("{000214F9-0000-0000-C000-000000000046}");
    const IID_IPersistFile = windows.GUID.parse("{0000010b-0000-0000-C000-000000000046}");
    const IID_IPropertyStore = windows.GUID.parse("{886d8eeb-8cf2-4446-8d02-cdba1dbdcf99}");

    const PROPERTYKEY = extern struct {
        fmtid: windows.GUID,
        pid: u32,
    };

    // System.AppUserModel.ID property key
    const PKEY_AppUserModel_ID = PROPERTYKEY{
        .fmtid = windows.GUID.parse("{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}"),
        .pid = 5,
    };

    // PROPVARIANT structure - simplified for our use case
    // In real Windows headers this has a complex nested union structure
    // We only need pwszVal for setting string properties
    const PROPVARIANT = extern struct {
        vt: u16,
        wReserved1: u16,
        wReserved2: u16,
        wReserved3: u16,
        // Union starts here - we only define pwszVal
        pwszVal: [*:0]const u16,
        // Padding to match full PROPVARIANT size
        _padding: [8]u8 = undefined,
    };

    const VT_LPWSTR: u16 = 31;

    const IPropertyStore = extern struct {
        v: *const VTable,

        pub const VTable = extern struct {
            QueryInterface: *anyopaque,
            AddRef: *anyopaque,
            Release: *anyopaque,
            GetCount: *anyopaque,
            GetAt: *anyopaque,
            GetValue: *anyopaque,
            SetValue: *const fn (*IPropertyStore, *const PROPERTYKEY, *const PROPVARIANT) callconv(.winapi) i32,
            Commit: *const fn (*IPropertyStore) callconv(.winapi) i32,
        };

        pub fn setValue(self: *IPropertyStore, key: *const PROPERTYKEY, value: *const PROPVARIANT) i32 {
            return self.v.SetValue(self, key, value);
        }

        pub fn commit(self: *IPropertyStore) i32 {
            return self.v.Commit(self);
        }

        pub fn release(self: *IPropertyStore) void {
            const Release = @as(*const fn (*IPropertyStore) callconv(.winapi) u32, @ptrCast(self.v.Release));
            _ = Release(self);
        }
    };

    const IShellLinkW = extern struct {
        v: *const VTable,

        pub const VTable = extern struct {
            QueryInterface: *const fn (*IShellLinkW, *const windows.GUID, *?*anyopaque) callconv(.winapi) i32,
            AddRef: *anyopaque,
            Release: *const fn (*IShellLinkW) callconv(.winapi) u32,
            GetArguments: *anyopaque,
            GetDescription: *anyopaque,
            GetHotkey: *anyopaque,
            GetIconLocation: *anyopaque,
            GetIDList: *anyopaque,
            GetPath: *anyopaque,
            GetShowCmd: *anyopaque,
            GetWorkingDirectory: *anyopaque,
            Resolve: *anyopaque,
            SetArguments: *const fn (*IShellLinkW, [*:0]const u16) callconv(.winapi) i32,  // offset 12
            SetDescription: *anyopaque,
            SetHotkey: *anyopaque,
            SetIconLocation: *anyopaque,
            SetIDList: *anyopaque,
            SetPath: *const fn (*IShellLinkW, [*:0]const u16) callconv(.winapi) i32,  // offset 17
            SetRelativePath: *anyopaque,
            SetShowCmd: *anyopaque,
            SetWorkingDirectory: *const fn (*IShellLinkW, [*:0]const u16) callconv(.winapi) i32,  // offset 20
        };

        pub fn setPath(self: *IShellLinkW, path: [*:0]const u16) i32 {
            return self.v.SetPath(self, path);
        }

        pub fn setArguments(self: *IShellLinkW, args: [*:0]const u16) i32 {
            return self.v.SetArguments(self, args);
        }

        pub fn setWorkingDirectory(self: *IShellLinkW, dir: [*:0]const u16) i32 {
            return self.v.SetWorkingDirectory(self, dir);
        }

        pub fn queryInterface(self: *IShellLinkW, riid: *const windows.GUID, ppv: *?*anyopaque) i32 {
            return self.v.QueryInterface(self, riid, ppv);
        }

        pub fn release(self: *IShellLinkW) void {
            _ = self.v.Release(self);
        }
    };

    const IPersistFile = extern struct {
        v: *const VTable,

        pub const VTable = extern struct {
            QueryInterface: *anyopaque,
            AddRef: *anyopaque,
            Release: *const fn (*IPersistFile) callconv(.winapi) u32,
            GetClassID: *anyopaque,
            IsDirty: *anyopaque,
            Load: *anyopaque,
            Save: *const fn (*IPersistFile, [*:0]const u16, i32) callconv(.winapi) i32,
            SaveCompleted: *anyopaque,
            GetCurFile: *anyopaque,
        };

        pub fn save(self: *IPersistFile, path: [*:0]const u16, remember: i32) i32 {
            return self.v.Save(self, path, remember);
        }

        pub fn release(self: *IPersistFile) void {
            _ = self.v.Release(self);
        }
    };

    /// Ensure Start Menu shortcut exists with AppUserModelID.
    /// Required for unpackaged desktop apps to show toast notifications.
    fn ensureShortcutExists(self: *WindowsBackend) !void {
        // Get APPDATA environment variable
        const appdata = std.process.getEnvVarOwned(self.allocator, "APPDATA") catch return error.AppDataNotFound;
        defer self.allocator.free(appdata);

        // Construct shortcut path
        const shortcut_path = try std.fmt.allocPrint(self.allocator, "{s}\\Microsoft\\Windows\\Start Menu\\Programs\\ZNotify.lnk", .{appdata});
        defer self.allocator.free(shortcut_path);

        // Convert to UTF-16 for Windows APIs
        const shortcut_path_w = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, shortcut_path);
        defer self.allocator.free(shortcut_path_w);

        // Always create/recreate shortcut to ensure it has proper AppUserModelID
        // (old shortcuts created without COM won't have the AUMID property)

        // Get current executable path
        var exe_path_buf: [windows.PATH_MAX_WIDE]u16 = undefined;
        const exe_path_wide = try self.getExePath(&exe_path_buf);

        // Get ole32 functions
        const ole32 = windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("ole32.dll")) orelse return error.Ole32NotFound;

        const CoCreateInstance = @as(*const fn (
            rclsid: *const windows.GUID,
            pUnkOuter: ?*anyopaque,
            dwClsContext: u32,
            riid: *const windows.GUID,
            ppv: *?*anyopaque,
        ) callconv(.winapi) i32, @ptrFromInt(@intFromPtr(
            windows.kernel32.GetProcAddress(ole32, "CoCreateInstance") orelse return error.CoCreateInstanceNotFound,
        )));


        const CLSCTX_INPROC_SERVER: u32 = 0x1;

        // Create IShellLink instance
        var shell_link_ptr: ?*anyopaque = null;
        var hr = CoCreateInstance(&CLSID_ShellLink, null, CLSCTX_INPROC_SERVER, &IID_IShellLinkW, &shell_link_ptr);
        if (hr < 0) return error.CoCreateInstanceFailed;

        const shell_link = @as(*IShellLinkW, @ptrCast(@alignCast(shell_link_ptr.?)));
        defer shell_link.release();

        // Set path - now at correct offset 17
        const lpcwstr_path: windows.LPCWSTR = @ptrCast(exe_path_wide.ptr);
        hr = shell_link.v.SetPath(shell_link, lpcwstr_path);
        if (hr < 0) {
            return error.SetPathFailed;
        }

        // Query for IPropertyStore interface
        var property_store_ptr: ?*anyopaque = null;
        hr = shell_link.queryInterface(&IID_IPropertyStore, &property_store_ptr);
        if (hr < 0) return error.QueryInterfaceFailed;

        const property_store = @as(*IPropertyStore, @ptrCast(@alignCast(property_store_ptr.?)));
        defer property_store.release();

        // Initialize PROPVARIANT with AUMID - matching C++ example
        const aumid_w = std.unicode.utf8ToUtf16LeStringLiteral(AUMID);
        var appIdPropVar = PROPVARIANT{
            .vt = VT_LPWSTR,
            .wReserved1 = 0,
            .wReserved2 = 0,
            .wReserved3 = 0,
            .pwszVal = aumid_w,
        };

        // Set AppUserModelID property
        hr = property_store.setValue(&PKEY_AppUserModel_ID, &appIdPropVar);
        if (hr < 0) return error.SetValueFailed;

        hr = property_store.commit();
        if (hr < 0) return error.CommitFailed;

        // Query for IPersistFile interface
        var persist_file_ptr: ?*anyopaque = null;
        hr = shell_link.queryInterface(&IID_IPersistFile, &persist_file_ptr);
        if (hr < 0) return error.QueryInterfaceFailed;

        const persist_file = @as(*IPersistFile, @ptrCast(@alignCast(persist_file_ptr.?)));
        defer persist_file.release();

        // Save the shortcut
        const shortcut_path_ptr: [*:0]const u16 = @ptrCast(shortcut_path_w.ptr);
        hr = persist_file.save(shortcut_path_ptr, 1); // TRUE = remember
        if (hr < 0) return error.SaveFailed;
    }

    /// Get the current executable path
    fn getExePath(self: *WindowsBackend, path_buf: []u16) ![:0]const u16 {
        _ = self;
        const len = windows.kernel32.GetModuleFileNameW(null, path_buf.ptr, @intCast(path_buf.len));
        if (len == 0) return error.GetModuleFileNameFailed;
        path_buf[len] = 0; // Add null terminator
        return path_buf[0..len :0];  // Return only the valid portion with sentinel
    }

    /// Initialize COM library for WinRT interop.
    fn initializeCOM(self: *WindowsBackend) !void {
        // Load ole32.dll (will increment ref count if already loaded)
        const ole32 = windows.kernel32.LoadLibraryW(std.unicode.utf8ToUtf16LeStringLiteral("ole32.dll"));
        if (ole32 == null) return error.Ole32NotFound;

        // CoInitializeEx with COINIT_APARTMENTTHREADED
        const CoInitializeEx = @as(*const fn (
            pvReserved: ?*anyopaque,
            dwCoInit: u32,
        ) callconv(.winapi) i32, @ptrFromInt(@intFromPtr(
            windows.kernel32.GetProcAddress(ole32.?, "CoInitializeEx") orelse return error.CoInitializeExNotFound,
        )));

        const COINIT_APARTMENTTHREADED: u32 = 0x2;
        const hr = CoInitializeEx(null, COINIT_APARTMENTTHREADED);

        // S_OK = 0: Successfully initialized, we own it
        // S_FALSE = 1: Already initialized by another caller, we don't own it
        // Negative: Error
        if (hr < 0) return error.ComInitFailed;

        // Only set com_initialized if WE initialized it (S_OK), not if it was already initialized (S_FALSE)
        self.com_initialized = (hr == 0);
    }

    /// Clean up Windows backend resources and uninitialize COM.
    pub fn deinit(self: *WindowsBackend) void {
        if (self.com_initialized) {
            const ole32 = windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("ole32.dll"));
            if (ole32) |handle| {
                const CoUninitialize = @as(*const fn () callconv(.winapi) void, @ptrFromInt(@intFromPtr(
                    windows.kernel32.GetProcAddress(handle, "CoUninitialize") orelse return,
                )));
                CoUninitialize();
            }
        }
        self.allocator.destroy(self);
    }

    /// Send notification via WinRT Toast API.
    /// Creates toast XML, displays notification, returns assigned ID.
    pub fn send(self: *WindowsBackend, notif: notification.Notification) !u32 {
        if (!self.available) {
            return errors.ZNotifyError.NotificationFailed;
        }

        // Build toast XML
        var xml_buf: [4096]u8 = undefined;
        const xml = try self.buildToastXml(&xml_buf, notif);

        // Show toast notification via WinRT
        try self.showToast(xml);

        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    /// Build Windows toast notification XML.
    /// Format: <toast><visual><binding template="ToastGeneric"><text>Title</text><text>Body</text></binding></visual></toast>
    pub fn buildToastXml(self: *WindowsBackend, buf: []u8, notif: notification.Notification) ![]const u8 {
        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        try writer.writeAll("<?xml version=\"1.0\" encoding=\"utf-8\"?>");

        // Map urgency to duration and scenario attributes
        const duration = switch (notif.urgency) {
            .low => "short",
            .normal, .critical => "long",
        };
        const scenario = switch (notif.urgency) {
            .critical => " scenario=\"urgent\"",
            else => "",
        };
        try writer.print("<toast duration=\"{s}\"{s}>", .{ duration, scenario });

        // Audio based on urgency
        // Note: Windows 11 may play Looping.Alarm once instead of looping
        const audio = switch (notif.urgency) {
            .low => "ms-winsoundevent:Notification.Default",
            .normal => "ms-winsoundevent:Notification.Default",
            .critical => "ms-winsoundevent:Notification.Looping.Alarm",
        };
        try writer.print("<audio src=\"{s}\"/>", .{audio});

        try writer.writeAll("<visual><binding template=\"ToastGeneric\">");

        // Title
        try writer.writeAll("<text>");
        try self.escapeXml(writer, notif.title);
        try writer.writeAll("</text>");

        // Body message
        if (notif.message.len > 0) {
            try writer.writeAll("<text>");
            try self.escapeXml(writer, notif.message);
            try writer.writeAll("</text>");
        }

        try writer.writeAll("</binding></visual></toast>");

        return stream.getWritten();
    }

    /// Escape XML special characters.
    fn escapeXml(_: *WindowsBackend, writer: anytype, text: []const u8) !void {
        for (text) |c| {
            switch (c) {
                '<' => try writer.writeAll("&lt;"),
                '>' => try writer.writeAll("&gt;"),
                '&' => try writer.writeAll("&amp;"),
                '"' => try writer.writeAll("&quot;"),
                '\'' => try writer.writeAll("&apos;"),
                else => try writer.writeByte(c),
            }
        }
    }

    /// Display toast notification using PowerShell as WinRT bridge.
    /// Uses PowerShell to access Windows.UI.Notifications APIs.
    fn showToast(self: *WindowsBackend, xml: []const u8) !void {
        // Create PowerShell script to show toast
        var ps_buf: [8192]u8 = undefined;
        const ps_script = try std.fmt.bufPrint(&ps_buf,
            \\try {{
            \\    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
            \\    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
            \\    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
            \\    $xml.LoadXml('{s}')
            \\    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
            \\    # Use our AUMID from the Start Menu shortcut
            \\    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('com.znotify.app')
            \\    $notifier.Show($toast)
            \\    Write-Output "Toast shown successfully"
            \\}} catch {{
            \\    Write-Error $_.Exception.Message
            \\    exit 1
            \\}}
        , .{xml});

        // Execute via PowerShell with output capture
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "powershell.exe",
                "-ExecutionPolicy",
                "Bypass",
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                ps_script,
            },
            .max_output_bytes = 1024 * 1024,
        }) catch |err| {
            return err;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.PowerShellFailed;
        }
    }

    /// Close/dismiss notification by ID.
    /// Windows doesn't provide direct API to close by our ID, so this is a no-op.
    pub fn close(_: *WindowsBackend, _: u32) !void {
        // Windows toast notifications auto-dismiss or stay in Action Center
        // No direct API to remove by our internal ID
    }

    /// Get backend capabilities.
    /// Caller owns returned memory.
    pub fn getCapabilities(self: *WindowsBackend, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "body,actions,images,sounds,persistence,history");
    }

    /// Check if Windows backend is available.
    pub fn isAvailable(self: *WindowsBackend) bool {
        return self.available;
    }

    /// VTable implementation for Windows backend.
    pub const vtable = backend.Backend.VTable{
        .init = @ptrCast(&WindowsBackend.init),
        .deinit = @ptrCast(&WindowsBackend.deinit),
        .send = @ptrCast(&WindowsBackend.send),
        .close = @ptrCast(&WindowsBackend.close),
        .getCapabilities = @ptrCast(&WindowsBackend.getCapabilities),
        .isAvailable = @ptrCast(&WindowsBackend.isAvailable),
    };
};

/// Create Windows notification backend.
/// Initializes COM and prepares WinRT Toast API access.
pub fn createBackend(allocator: std.mem.Allocator) !backend.Backend {
    const windows_backend = try WindowsBackend.init(allocator);
    return backend.Backend{
        .ptr = windows_backend,
        .vtable = &WindowsBackend.vtable,
    };
}
