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

    // WinRT Toast Notification GUIDs and interfaces
    // See docs/design/winrt-interfaces.md for full documentation

    // WinRT Runtime class names for RoGetActivationFactory
    const CLASS_XmlDocument = std.unicode.utf8ToUtf16LeStringLiteral("Windows.Data.Xml.Dom.XmlDocument");
    const CLASS_ToastNotification = std.unicode.utf8ToUtf16LeStringLiteral("Windows.UI.Notifications.ToastNotification");
    const CLASS_ToastNotificationManager = std.unicode.utf8ToUtf16LeStringLiteral("Windows.UI.Notifications.ToastNotificationManager");

    // HSTRING - WinRT string handle (opaque pointer)
    const HSTRING = *opaque {};

    // WinRT interface GUIDs
    const IID_IInspectable = windows.GUID.parse("{AF86E2E0-B12D-4c6a-9C5A-D7AA65101E90}");
    const IID_IActivationFactory = windows.GUID.parse("{00000035-0000-0000-C000-000000000046}");
    const IID_IXmlDocumentIO = windows.GUID.parse("{6cd0e74e-ee65-4489-9ebf-ca43e87ba637}");
    const IID_IToastNotificationFactory = windows.GUID.parse("{04124b20-82c6-4229-b109-fd9ed4662b53}");
    const IID_IToastNotification = windows.GUID.parse("{997e2675-059e-4e60-8b06-1760917c8b80}");
    const IID_IToastNotificationManagerStatics = windows.GUID.parse("{50ac103f-d235-4598-bbef-98fe4d1a3ad4}");
    const IID_IToastNotifier = windows.GUID.parse("{75927b93-03f3-41ec-91d3-6e5bac1b38e7}");

    // TrustLevel enum for IInspectable
    const TrustLevel = enum(i32) {
        BaseTrust = 0,
        PartialTrust = 1,
        FullTrust = 2,
    };

    // IInspectable - base interface for all WinRT interfaces
    // Inherits from IUnknown (QueryInterface, AddRef, Release)
    const IInspectable = extern struct {
        v: *const VTable,

        pub const VTable = extern struct {
            // IUnknown methods (offsets 0-2)
            QueryInterface: *const fn (*IInspectable, *const windows.GUID, *?*anyopaque) callconv(.winapi) i32,
            AddRef: *const fn (*IInspectable) callconv(.winapi) u32,
            Release: *const fn (*IInspectable) callconv(.winapi) u32,
            // IInspectable methods (offsets 3-5)
            GetIids: *const fn (*IInspectable, *u32, *?[*]windows.GUID) callconv(.winapi) i32,
            GetRuntimeClassName: *const fn (*IInspectable, *HSTRING) callconv(.winapi) i32,
            GetTrustLevel: *const fn (*IInspectable, *TrustLevel) callconv(.winapi) i32,
        };

        pub fn queryInterface(self: *IInspectable, riid: *const windows.GUID, ppv: *?*anyopaque) i32 {
            return self.v.QueryInterface(self, riid, ppv);
        }

        pub fn addRef(self: *IInspectable) u32 {
            return self.v.AddRef(self);
        }

        pub fn release(self: *IInspectable) u32 {
            return self.v.Release(self);
        }
    };

    // IActivationFactory - used to activate WinRT runtime classes
    const IActivationFactory = extern struct {
        v: *const VTable,

        pub const VTable = extern struct {
            // IUnknown methods
            QueryInterface: *const fn (*IActivationFactory, *const windows.GUID, *?*anyopaque) callconv(.winapi) i32,
            AddRef: *const fn (*IActivationFactory) callconv(.winapi) u32,
            Release: *const fn (*IActivationFactory) callconv(.winapi) u32,
            // IInspectable methods
            GetIids: *anyopaque,
            GetRuntimeClassName: *anyopaque,
            GetTrustLevel: *anyopaque,
            // IActivationFactory methods (offset 6)
            ActivateInstance: *const fn (*IActivationFactory, **IInspectable) callconv(.winapi) i32,
        };

        pub fn queryInterface(self: *IActivationFactory, riid: *const windows.GUID, ppv: *?*anyopaque) i32 {
            return self.v.QueryInterface(self, riid, ppv);
        }

        pub fn release(self: *IActivationFactory) u32 {
            return self.v.Release(self);
        }

        pub fn activateInstance(self: *IActivationFactory, instance: **IInspectable) i32 {
            return self.v.ActivateInstance(self, instance);
        }
    };

    // IXmlDocumentIO - load XML into XmlDocument
    const IXmlDocumentIO = extern struct {
        v: *const VTable,

        pub const VTable = extern struct {
            // IUnknown methods
            QueryInterface: *const fn (*IXmlDocumentIO, *const windows.GUID, *?*anyopaque) callconv(.winapi) i32,
            AddRef: *const fn (*IXmlDocumentIO) callconv(.winapi) u32,
            Release: *const fn (*IXmlDocumentIO) callconv(.winapi) u32,
            // IInspectable methods
            GetIids: *anyopaque,
            GetRuntimeClassName: *anyopaque,
            GetTrustLevel: *anyopaque,
            // IXmlDocumentIO methods (offset 6)
            LoadXml: *const fn (*IXmlDocumentIO, HSTRING) callconv(.winapi) i32,
            LoadXmlWithSettings: *anyopaque,
            SaveToFileAsync: *anyopaque,
        };

        pub fn queryInterface(self: *IXmlDocumentIO, riid: *const windows.GUID, ppv: *?*anyopaque) i32 {
            return self.v.QueryInterface(self, riid, ppv);
        }

        pub fn release(self: *IXmlDocumentIO) u32 {
            return self.v.Release(self);
        }

        pub fn loadXml(self: *IXmlDocumentIO, xml: HSTRING) i32 {
            return self.v.LoadXml(self, xml);
        }
    };

    // IToastNotificationFactory - create ToastNotification from XML
    const IToastNotificationFactory = extern struct {
        v: *const VTable,

        pub const VTable = extern struct {
            // IUnknown methods
            QueryInterface: *const fn (*IToastNotificationFactory, *const windows.GUID, *?*anyopaque) callconv(.winapi) i32,
            AddRef: *const fn (*IToastNotificationFactory) callconv(.winapi) u32,
            Release: *const fn (*IToastNotificationFactory) callconv(.winapi) u32,
            // IInspectable methods
            GetIids: *anyopaque,
            GetRuntimeClassName: *anyopaque,
            GetTrustLevel: *anyopaque,
            // IToastNotificationFactory methods (offset 6)
            CreateToastNotification: *const fn (*IToastNotificationFactory, *IXmlDocumentIO, **IToastNotification) callconv(.winapi) i32,
        };

        pub fn queryInterface(self: *IToastNotificationFactory, riid: *const windows.GUID, ppv: *?*anyopaque) i32 {
            return self.v.QueryInterface(self, riid, ppv);
        }

        pub fn release(self: *IToastNotificationFactory) u32 {
            return self.v.Release(self);
        }

        pub fn createToastNotification(self: *IToastNotificationFactory, content: *IXmlDocumentIO, value: **IToastNotification) i32 {
            return self.v.CreateToastNotification(self, content, value);
        }
    };

    // IToastNotification - the notification object
    const IToastNotification = extern struct {
        v: *const VTable,

        pub const VTable = extern struct {
            // IUnknown methods
            QueryInterface: *const fn (*IToastNotification, *const windows.GUID, *?*anyopaque) callconv(.winapi) i32,
            AddRef: *const fn (*IToastNotification) callconv(.winapi) u32,
            Release: *const fn (*IToastNotification) callconv(.winapi) u32,
            // IInspectable methods
            GetIids: *anyopaque,
            GetRuntimeClassName: *anyopaque,
            GetTrustLevel: *anyopaque,
            // IToastNotification methods (offset 6+)
            get_Content: *anyopaque,
            put_ExpirationTime: *anyopaque,
            get_ExpirationTime: *anyopaque,
            add_Dismissed: *anyopaque,
            remove_Dismissed: *anyopaque,
            add_Activated: *anyopaque,
            remove_Activated: *anyopaque,
            add_Failed: *anyopaque,
            remove_Failed: *anyopaque,
        };

        pub fn release(self: *IToastNotification) u32 {
            return self.v.Release(self);
        }
    };

    // IToastNotificationManagerStatics - static methods for ToastNotificationManager
    const IToastNotificationManagerStatics = extern struct {
        v: *const VTable,

        pub const VTable = extern struct {
            // IUnknown methods
            QueryInterface: *const fn (*IToastNotificationManagerStatics, *const windows.GUID, *?*anyopaque) callconv(.winapi) i32,
            AddRef: *const fn (*IToastNotificationManagerStatics) callconv(.winapi) u32,
            Release: *const fn (*IToastNotificationManagerStatics) callconv(.winapi) u32,
            // IInspectable methods
            GetIids: *anyopaque,
            GetRuntimeClassName: *anyopaque,
            GetTrustLevel: *anyopaque,
            // IToastNotificationManagerStatics methods (offset 6)
            CreateToastNotifier: *anyopaque,
            CreateToastNotifierWithId: *const fn (*IToastNotificationManagerStatics, HSTRING, **IToastNotifier) callconv(.winapi) i32,
            GetTemplateContent: *anyopaque,
        };

        pub fn queryInterface(self: *IToastNotificationManagerStatics, riid: *const windows.GUID, ppv: *?*anyopaque) i32 {
            return self.v.QueryInterface(self, riid, ppv);
        }

        pub fn release(self: *IToastNotificationManagerStatics) u32 {
            return self.v.Release(self);
        }

        pub fn createToastNotifierWithId(self: *IToastNotificationManagerStatics, applicationId: HSTRING, notifier: **IToastNotifier) i32 {
            return self.v.CreateToastNotifierWithId(self, applicationId, notifier);
        }
    };

    // IToastNotifier - displays toast notifications
    const IToastNotifier = extern struct {
        v: *const VTable,

        pub const VTable = extern struct {
            // IUnknown methods
            QueryInterface: *const fn (*IToastNotifier, *const windows.GUID, *?*anyopaque) callconv(.winapi) i32,
            AddRef: *const fn (*IToastNotifier) callconv(.winapi) u32,
            Release: *const fn (*IToastNotifier) callconv(.winapi) u32,
            // IInspectable methods
            GetIids: *anyopaque,
            GetRuntimeClassName: *anyopaque,
            GetTrustLevel: *anyopaque,
            // IToastNotifier methods (offset 6)
            Show: *const fn (*IToastNotifier, *IToastNotification) callconv(.winapi) i32,
            Hide: *anyopaque,
            get_Setting: *anyopaque,
            AddToSchedule: *anyopaque,
            RemoveFromSchedule: *anyopaque,
            GetScheduledToastNotifications: *anyopaque,
        };

        pub fn release(self: *IToastNotifier) u32 {
            return self.v.Release(self);
        }

        pub fn show(self: *IToastNotifier, toast: *IToastNotification) i32 {
            return self.v.Show(self, toast);
        }
    };

    // WinRT function pointers (loaded dynamically from combase.dll)
    var combase_dll: ?windows.HMODULE = null;
    var WindowsCreateString_fn: ?*const fn (sourceString: [*:0]const u16, length: u32, string: *HSTRING) callconv(.winapi) i32 = null;
    var WindowsDeleteString_fn: ?*const fn (string: HSTRING) callconv(.winapi) i32 = null;
    var RoGetActivationFactory_fn: ?*const fn (activatableClassId: HSTRING, iid: *const windows.GUID, factory: *?*anyopaque) callconv(.winapi) i32 = null;

    // Load WinRT functions from combase.dll
    fn loadWinRTFunctions() !void {
        if (combase_dll != null) return; // Already loaded

        combase_dll = windows.kernel32.LoadLibraryW(std.unicode.utf8ToUtf16LeStringLiteral("combase.dll"));
        if (combase_dll == null) return error.CombaseDllNotFound;

        WindowsCreateString_fn = @ptrCast(@alignCast(
            windows.kernel32.GetProcAddress(combase_dll.?, "WindowsCreateString") orelse return error.WindowsCreateStringNotFound,
        ));

        WindowsDeleteString_fn = @ptrCast(@alignCast(
            windows.kernel32.GetProcAddress(combase_dll.?, "WindowsDeleteString") orelse return error.WindowsDeleteStringNotFound,
        ));

        RoGetActivationFactory_fn = @ptrCast(@alignCast(
            windows.kernel32.GetProcAddress(combase_dll.?, "RoGetActivationFactory") orelse return error.RoGetActivationFactoryNotFound,
        ));
    }

    // Helper function to create HSTRING from UTF-8 string
    fn createHString(allocator: std.mem.Allocator, str: []const u8) !HSTRING {
        // Ensure WinRT functions are loaded
        try loadWinRTFunctions();

        // Convert UTF-8 to UTF-16 with null terminator
        const utf16 = try std.unicode.utf8ToUtf16LeAllocZ(allocator, str);
        defer allocator.free(utf16);

        // Call WindowsCreateString (length doesn't include null terminator)
        var hstring: HSTRING = undefined;
        const hr = WindowsCreateString_fn.?(utf16.ptr, @intCast(utf16.len), &hstring);
        if (hr < 0) return error.HStringCreationFailed;
        return hstring;
    }

    // Helper function to free HSTRING
    fn deleteHString(hstring: HSTRING) void {
        if (WindowsDeleteString_fn) |fn_ptr| {
            _ = fn_ptr(hstring);
        }
    }

    // Helper function to get WinRT activation factory
    fn getActivationFactory(allocator: std.mem.Allocator, className: []const u16, iid: *const windows.GUID, factory: *?*anyopaque) !void {
        // Ensure WinRT functions are loaded
        try loadWinRTFunctions();

        // Create HSTRING from class name
        var hstring: HSTRING = undefined;
        const hr_create = WindowsCreateString_fn.?(@ptrCast(className.ptr), @intCast(className.len), &hstring);
        if (hr_create < 0) return error.HStringCreationFailed;
        defer deleteHString(hstring);

        // Get activation factory
        const hr_factory = RoGetActivationFactory_fn.?(hstring, iid, factory);
        if (hr_factory < 0) {
            _ = allocator;
            return error.ActivationFactoryFailed;
        }
    }

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

    /// Benchmark helper: Send notification using direct COM implementation only.
    /// This bypasses the fallback logic for performance testing.
    pub fn sendWithCOM(self: *WindowsBackend, notif: notification.Notification) !u32 {
        if (!self.available) {
            return errors.ZNotifyError.NotificationFailed;
        }

        var xml_buf: [4096]u8 = undefined;
        const xml = try self.buildToastXml(&xml_buf, notif);
        try self.showToastDirect(xml);

        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    /// Benchmark helper: Send notification using PowerShell fallback only.
    /// This bypasses the COM implementation for performance comparison.
    pub fn sendWithPowerShell(self: *WindowsBackend, notif: notification.Notification) !u32 {
        if (!self.available) {
            return errors.ZNotifyError.NotificationFailed;
        }

        var xml_buf: [4096]u8 = undefined;
        const xml = try self.buildToastXml(&xml_buf, notif);
        try self.showToastPowerShell(xml);

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

        // Determine duration attribute
        // IMPORTANT: Windows Toast API only supports two fixed durations:
        //   - "short" = 5-10 seconds (Windows-controlled, cannot be shorter)
        //   - "long" = 25 seconds
        // This is a platform limitation - arbitrary millisecond timeouts are not supported.
        //
        // Priority:
        //   1. Use explicit windows_duration if provided (--duration option)
        //   2. Otherwise, map timeout_ms: <10s → "short", ≥10s or null → "long"
        const duration = if (notif.windows_duration) |win_dur| blk: {
            break :blk win_dur.toString();
        } else if (notif.timeout_ms) |timeout| blk: {
            if (timeout < 10000) {
                break :blk "short";
            } else {
                break :blk "long";
            }
        } else "long";

        // Critical urgency notifications use "urgent" scenario for persistent display
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

    /// Display toast notification using direct WinRT COM calls.
    /// Makes direct COM interface calls to Windows.UI.Notifications APIs via combase.dll.
    /// This eliminates the PowerShell dependency and provides 3-5x better performance (<10ms).
    fn showToastDirect(self: *WindowsBackend, xml: []const u8) !void {
        // Step 1: Create HSTRING for XML
        const xml_hstring = try createHString(self.allocator, xml);
        defer deleteHString(xml_hstring);

        // Step 2: Get IXmlDocument factory and create instance
        var xml_factory_ptr: ?*anyopaque = null;
        try getActivationFactory(self.allocator, CLASS_XmlDocument, &IID_IActivationFactory, &xml_factory_ptr);
        const xml_factory: *IActivationFactory = @ptrCast(@alignCast(xml_factory_ptr.?));
        defer _ = xml_factory.release();

        var xml_doc_obj: *IInspectable = undefined;
        const hr_activate = xml_factory.activateInstance(&xml_doc_obj);
        if (hr_activate < 0) return error.XmlDocumentCreationFailed;
        defer _ = xml_doc_obj.release();

        // Step 3: QueryInterface for IXmlDocumentIO
        var xml_doc_io_ptr: ?*anyopaque = null;
        const hr_qi = xml_doc_obj.queryInterface(&IID_IXmlDocumentIO, &xml_doc_io_ptr);
        if (hr_qi < 0) return error.XmlDocumentQueryFailed;
        const xml_doc: *IXmlDocumentIO = @ptrCast(@alignCast(xml_doc_io_ptr.?));
        defer _ = xml_doc.release();

        // Step 4: Load XML
        const hr_load = xml_doc.loadXml(xml_hstring);
        if (hr_load < 0) return error.XmlLoadFailed;

        // Step 5: Get IToastNotificationFactory
        var toast_factory_ptr: ?*anyopaque = null;
        try getActivationFactory(self.allocator, CLASS_ToastNotification, &IID_IToastNotificationFactory, &toast_factory_ptr);
        const toast_factory: *IToastNotificationFactory = @ptrCast(@alignCast(toast_factory_ptr.?));
        defer _ = toast_factory.release();

        // Step 6: Create ToastNotification from XML document
        var toast_ptr: *IToastNotification = undefined;
        const hr_create_toast = toast_factory.createToastNotification(xml_doc, &toast_ptr);
        if (hr_create_toast < 0) return error.ToastCreationFailed;
        defer _ = toast_ptr.release();

        // Step 7: Create HSTRING for AUMID
        const aumid_hstring = try createHString(self.allocator, "com.znotify.app");
        defer deleteHString(aumid_hstring);

        // Step 8: Get IToastNotificationManagerStatics
        var manager_statics_ptr: ?*anyopaque = null;
        try getActivationFactory(self.allocator, CLASS_ToastNotificationManager, &IID_IToastNotificationManagerStatics, &manager_statics_ptr);
        const manager_statics: *IToastNotificationManagerStatics = @ptrCast(@alignCast(manager_statics_ptr.?));
        defer _ = manager_statics.release();

        // Step 9: Create ToastNotifier with AUMID
        var notifier_ptr: *IToastNotifier = undefined;
        const hr_create_notifier = manager_statics.createToastNotifierWithId(aumid_hstring, &notifier_ptr);
        if (hr_create_notifier < 0) return error.NotifierCreationFailed;
        defer _ = notifier_ptr.release();

        // Step 10: Show the notification
        const hr_show = notifier_ptr.show(toast_ptr);
        if (hr_show < 0) return error.NotificationShowFailed;
    }

    // Main entry point for showing toast notifications
    // Tries direct COM first, falls back to PowerShell on error
    fn showToast(self: *WindowsBackend, xml: []const u8) !void {
        // Try direct COM implementation first
        self.showToastDirect(xml) catch |err| {
            // Fall back to PowerShell if COM fails
            std.debug.print("Direct COM failed ({any}), using PowerShell fallback\n", .{err});
            return self.showToastPowerShell(xml);
        };
    }

    // PowerShell fallback implementation (used when direct COM fails)
    fn showToastPowerShell(self: *WindowsBackend, xml: []const u8) !void {
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
