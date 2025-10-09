# Backend Implementation Roadmap

This document tracks the implementation status and planned features for all platform backends.

## Current Status Summary

| Feature | Windows | Linux | macOS |
|---------|---------|-------|-------|
| Basic notification (title + message) | ✅ | ✅ | ✅ |
| COM/Framework initialization | ✅ | ✅ | ✅ |
| AppUserModelID / shortcut creation | ✅ | N/A | N/A |
| Icon support | ❌ | ✅ | ❌ |
| Urgency levels | ✅ | ✅ | ❌ |
| Timeout/duration | ⚠️ Hardcoded | ✅ | ❌ |
| Notification updates (replaces_id) | ❌ | ✅ | ❌ |
| Capability detection | N/A | ✅ | N/A |
| Action buttons | ❌ | ✅ | ❌ |
| Sound/audio | ✅ | ❌ | ❌ |
| Notification ID tracking | ❌ | ✅ | ✅ |
| Click activation handling | ❌ | ❌ | ❌ |
| Error handling | ⚠️ Basic | ✅ | ✅ |

**Legend:**
- ✅ Fully implemented
- ⚠️ Partially implemented or needs improvement
- ❌ Not implemented

## Platform-Specific Details

### Windows Backend

**Status:** Core functionality working, enhancements needed

#### ✅ Completed (Phase 1)
- [x] COM initialization and cleanup
- [x] Start Menu shortcut creation with AppUserModelID
- [x] WinRT Toast XML generation
- [x] Basic notification display (title + message)
- [x] **Direct WinRT COM Implementation**
  - Dynamically load combase.dll functions (WindowsCreateString, WindowsDeleteString, RoGetActivationFactory)
  - Direct COM interface calls to Windows.Data.Xml.Dom.XmlDocument
  - Direct COM interface calls to Windows.UI.Notifications.ToastNotification
  - Direct COM interface calls to Windows.UI.Notifications.ToastNotificationManager
  - PowerShell fallback for compatibility (automatic on COM failure)
- [x] Default notification sound
- [x] **Urgency Level Mapping**
  - Map `Urgency.low` → `duration="short"` (5-10s display)
  - Map `Urgency.normal` → `duration="long"` (25s display)
  - Map `Urgency.critical` → `duration="long"` + `scenario="urgent"` (persistent, alarm sound)
  - Note: Windows 11 may play alarm once instead of looping despite "Looping.Alarm" URI

#### ✅ Completed (Phase 1 - continued)
- [x] **Timeout Handling** (P0)
  - Respect notification.timeout_ms parameter (with platform limitations)
  - Map timeout_ms < 10000 to "short" duration (~5-10s auto-dismiss)
  - Map timeout_ms >= 10000 to "long" duration (~25s auto-dismiss)
  - Null or 0 timeout uses "long" for user-controlled dismissal
  - **Platform Limitation**: Windows Toast API only supports two fixed durations ("short" and "long"), not arbitrary millisecond values. Minimum effective timeout is ~5 seconds.

#### 📋 TODO (Phase 2)
- [ ] **Custom Icon Support** (P1)
  - Support local file paths in toast XML
  - Support app resources (ms-appx:// protocol)
  - Convert common image formats to compatible types
  - Fallback to application icon

- [ ] **Action Buttons** (P1)
  - Add `<actions>` to toast XML
  - Support up to 5 buttons per notification
  - Button click handling via COM activation

- [x] **Audio Customization - Basic** (P2)
  - ✅ Urgency-based sounds (default, looping alarm for critical)
  - ✅ Map to ms-winsoundevent URIs
  - [ ] TODO: User-customizable sounds (CLI option)
  - [ ] TODO: Silent notifications option

- [ ] **Shell_NotifyIcon Fallback** (P1)
  - Detect Windows 8.1 and earlier
  - Implement balloon notification fallback
  - System tray icon management

- [ ] **Activation Handling** (P2)
  - Implement COM activation handler
  - Handle toast clicks and dismissals
  - Execute callback commands

- [ ] **Notification ID Tracking** (P1)
  - Return Windows notification tag/group
  - Enable notification updates
  - Enable notification removal

#### Technical Notes
- **Direct COM Implementation**: Uses direct WinRT COM calls via dynamically loaded combase.dll functions. Eliminates PowerShell dependency for significantly improved performance (<10ms vs 30-50ms). PowerShell fallback remains available for compatibility.
- **AUMID Requirement**: Shortcut creation is mandatory for unpackaged apps. Must run on first use.
- **Windows 8.1 Support**: Need to test fallback on older Windows versions.
- **Performance**: Shortcut creation adds ~100ms to first notification. Cache shortcut existence check.

---

### Linux Backend

**Status:** ✅ Phase 2 Complete - Full feature implementation

#### ✅ Completed (Phase 1 & 2)
- [x] Platform detection
- [x] Basic backend structure
- [x] Error types defined
- [x] **D-Bus Connection** (P0)
  - Connect to session bus via UNIX socket
  - EXTERNAL authentication with UID
  - Hello() handshake for connection establishment
  - Handle org.freedesktop.Notifications interface
  - Method: `Notify(app_name, replaces_id, app_icon, summary, body, actions, hints, timeout)`
- [x] **Basic Notification Display** (P0)
  - Send title as `summary`
  - Send message as `body`
  - Use app_name = "znotify"
  - Return notification ID from daemon
- [x] **Urgency Level Support** (P0)
  - Map to `urgency` hint (0=low, 1=normal, 2=critical)
  - Properly encode D-Bus `a{sv}` hints dictionary
  - Visual distinction works with mako/dunst configuration
- [x] **Timeout Handling** (P0)
  - Pass notification.timeout_ms to D-Bus Notify as int32
  - Special value -1 for default timeout
  - Special value 0 for never expires (persistent notifications)
- [x] **Icon Support** (P1)
  - Support file paths for local images
  - Support icon theme names (e.g., "dialog-information")
  - CLI integration via -i/--icon option
- [x] **Capabilities Detection** (P1)
  - Call GetCapabilities to detect daemon features
  - Parse array of strings from D-Bus response
  - Helper functions: hasCapability, supportsActions, supportsIcons, supportsBodyMarkup
- [x] **Notification Updates** (P1)
  - Use replaces_id to update existing notifications
  - CLI integration via -r/--replace-id option
  - Daemon returns same ID when replacing
- [x] **Action Buttons** (P1)
  - Pass actions array to D-Bus in proper format
  - Format: ["action1", "Label 1", "action2", "Label 2"]
  - CLI integration via --action <id> <label> option (repeatable)
  - Test coverage with capability detection
  - Note: Mako daemon uses CLI-based invocation (`makoctl invoke`/`makoctl menu`) rather than visual buttons; GNOME/KDE/Dunst show visual buttons
- [x] **ActionInvoked Signal Handler** (P2)
  - Subscribe to ActionInvoked D-Bus signals using AddMatch
  - Parse signal messages to extract notification ID and action key
  - Filter signals by interface and member (skip NameAcquired, NameLost, etc.)
  - Use same D-Bus connection for sending and receiving (Dunst requirement)
  - CLI integration via --wait flag (blocks until action is invoked)
  - Test coverage with automated signal sending
- [x] **Wait Timeout Implementation** (P2)
  - Implement timeout support using poll() for non-blocking waits
  - CLI integration via --wait-timeout=<ms> option
  - Returns error.Timeout when no action clicked within timeout period
  - Supports infinite wait (0 or omitted timeout)

#### 🚧 In Progress / Needs Work
None - Phase 3 complete!

#### 📋 TODO (Phase 4 - Advanced Features)

- [ ] **Sound Support** (P2)
  - Use `sound-file` hint for custom sounds
  - Use `sound-name` hint for theme sounds
  - Suppress sound with `suppress-sound` hint

- [ ] **Notification Closure** (P2)
  - Implement NotificationClosed signal handler
  - Track closure reason (expired, dismissed, closed by call)
  - Execute callbacks on closure

- [ ] **Advanced Hints** (P2)
  - Image data embedding via `image-data` hint
  - Category hints for notification grouping
  - Transient hint for non-persistent notifications
  - Resident hint for notifications that stay until explicitly closed

#### Technical Notes
- **D-Bus Implementation**: Using pure Zig D-Bus binary protocol implementation (zero dependencies)
  - Direct UNIX socket communication
  - Manual message marshalling with proper alignment handling
  - EXTERNAL authentication with UID
  - No dependency on libdbus-1.so
- **Daemon Compatibility**: Tested with Dunst and Mako, compatible with notify-osd, GNOME Shell, KDE Plasma, XFCE4-notifyd
- **X11 vs Wayland**: Protocol is compositor-agnostic via D-Bus
- **Testing**: Modular test suite in src/tests/linux_backend_test.zig, Docker support available

---

### macOS Backend

**Status:** ✅ Phase 1 Complete - Core functionality working

#### ✅ Completed (Phase 1 - Core)
- [x] Platform detection
- [x] Basic backend structure
- [x] Error types defined
- [x] **Custom Objective-C Runtime Bindings** (P0)
  - Implemented objc.zig (~170 lines) with zero external dependencies
  - Custom msgSend implementation with comptime function type generation
  - Objective-C block support for completion handlers
  - Class and Object wrapper types
  - No dependency on other external libraries
- [x] **Framework Initialization** (P0)
  - UserNotifications framework (requires macOS 10.14+)
  - Runtime version detection (handles both 10.x and 11+ versioning scheme)
  - App bundle detection (UNUserNotificationCenter requires running from app bundle)
- [x] **UNUserNotificationCenter Implementation** (P0)
  - Proper authorization request using requestAuthorizationWithOptions:completionHandler:
  - Block-based completion handler for authorization response
  - Create UNMutableNotificationContent
  - Set title and body (with null-terminated string handling)
  - Create UNNotificationRequest with unique identifiers
  - Schedule notification via addNotificationRequest
- [x] **Basic Notification Display** (P0)
  - Title and message support
  - Return notification identifier (incrementing u32)
- [x] **App Bundle Infrastructure**
  - ZNotify.app bundle structure with Info.plist
  - Automatic ad-hoc code signing in build system
  - CFRunLoop integration (0.2s for async notification dispatch)
- [x] **Test Infrastructure**
  - Tests run from within app bundle (provides bundle context)
  - 5 comprehensive tests (init, send, version detection, urgency, timeout)
  - Solves UNUserNotificationCenter testing challenge (requires bundle identifier)

#### 🚧 In Progress / Needs Work
None - Phase 1 complete, ready for Phase 2 features.

#### 📋 TODO (Phase 2 - Features)
- [ ] **Icon Support** (P1)
  - Use app icon automatically
  - Custom icon via UNNotificationAttachment
  - Support local file paths

- [ ] **Urgency/Priority Levels** (P1)
  - Map to UNNotificationInterruptionLevel
  - .passive (low), .active (normal), .timeSensitive (critical)
  - Requires special entitlement for timeSensitive

- [ ] **Timeout Handling** (P1)
  - Configure via UNNotificationSettings
  - System controls display duration
  - May not support custom timeouts

- [ ] **Action Buttons** (P1)
  - Define UNNotificationAction objects
  - Create UNNotificationCategory
  - Register categories with center
  - Implement delegate for action responses

- [ ] **Sound Support** (P2)
  - Set UNNotificationSound
  - Default, custom, or silent
  - Support for system sounds

- [ ] **Notification Updates** (P2)
  - Use same identifier to replace
  - Remove delivered notifications

- [ ] **Click Handling** (P2)
  - Implement UNUserNotificationCenterDelegate
  - Handle userNotificationCenter(_:didReceive:)
  - Execute callback commands

#### Technical Notes
- **Objective-C Interop**: Custom implementation in objc.zig (~170 lines) with zero external dependencies
  - msgSend with comptime function type generation (not variadic)
  - Block literal support matching LLVM block runtime ABI
  - BlockDescriptor, BlockFlags structures for completion handlers
  - Direct C runtime calls only (objc_msgSend, sel_registerName, objc_getClass)
  - No dependency on external libraries
- **Framework Linking**: Foundation, CoreFoundation, AppKit, UserNotifications frameworks linked
- **App Bundle Requirement**: UNUserNotificationCenter requires running from a valid .app bundle with Info.plist and bundle identifier
- **Code Signing**: Ad-hoc signing (`codesign --sign -`) sufficient for local development; distribution requires Apple Developer ID
- **Authorization**: Proper requestAuthorizationWithOptions:completionHandler: implementation with block-based callback
  - Follows Apple's guideline: "Always call this method before scheduling any local notifications"
  - Block signature: void (^)(BOOL granted, NSError *error)
  - System caches authorization, safe to call on every notification send
  - 200ms sleep after request to allow authorization dialog to complete
- **Version Requirement**: macOS 10.14+ (Mojave) required for UNUserNotificationCenter
- **CFRunLoop**: 0.2s event loop required after sending to allow async notification dispatch before process exit
- **Testing Challenge**: Tests must run from within app bundle to access UNUserNotificationCenter (solved via build.zig placing test executable in ZNotify.app/Contents/MacOS/)
- **Version Detection**: Handles Apple's versioning scheme change from 10.x to 11, 12, 13... 26 (macOS Tahoe)
- **String Handling**: Null-terminated string copies required for NSString stringWithUTF8String: (notif.title/message are not null-terminated)

---

## Implementation Phases

### Phase 0: Foundation (COMPLETED)
- ✅ Platform abstraction layer
- ✅ Backend interface definition
- ✅ Windows core implementation
- ✅ Cross-platform testing infrastructure

### Phase 1: Core Functionality (CURRENT)
**Priority:** Get basic notifications working on all three platforms

**Linux (Immediate):**
1. D-Bus connection and basic Notify method
2. Title + message display
3. Urgency levels
4. Timeout handling
5. Integration tests with Docker/Dunst

**macOS (Next):**
1. Framework initialization and version detection
2. UNUserNotificationCenter implementation
3. Title + message display
4. Authorization handling
5. App bundle requirement enforcement

**Windows (Refinement):**
1. Fix urgency level mapping
2. Proper timeout handling
3. Performance optimization (cache shortcut check)

### Phase 2: Feature Parity
**Priority:** Match notify-send feature set

**All Platforms:**
1. Custom icon support
2. Notification ID tracking and updates
3. Action buttons (where supported)
4. Sound customization
5. Error handling improvements

### Phase 3: Platform-Specific Enhancements
**Priority:** Leverage unique platform capabilities

**Windows:**
- [x] Direct WinRT COM calls (eliminate PowerShell) - **COMPLETED**
- [ ] COM activation handler for callbacks
- [ ] Shell_NotifyIcon fallback for Windows 8.1

**Linux:**
- Full capabilities detection
- Signal handling (ActionInvoked, NotificationClosed)
- Resident notifications (timeout=0)

**macOS:**
- Notification categories and actions
- Rich media attachments
- Critical alerts (with entitlement)

### Phase 4: Polish & Optimization
**Priority:** Production readiness

**All Platforms:**
- Comprehensive error messages
- Performance benchmarking
- Memory leak detection
- Edge case handling
- Accessibility features
- Dark mode icon variants

---

## Feature Priority Matrix

### P0 (Must Have - Required for v1.0)
- Basic notification display (title + message)
- Platform initialization/cleanup
- Urgency level support
- Timeout handling
- Basic error handling
- Notification ID return

### P1 (Should Have - Required for notify-send compatibility)
- Custom icon support
- Notification updates (by ID)
- Action buttons (Linux/macOS)
- Capabilities detection (Linux)
- Fallback implementations (Windows 8.1)

### P2 (Nice to Have - Enhanced features)
- Sound customization
- Click activation callbacks
- Notification closure tracking
- Rich media attachments
- Progress bars
- Critical alerts

### P3 (Future Enhancements)
- Notification history
- Desktop-specific themes
- Animation control
- Multi-monitor positioning
- Grouping/threading

---

## Testing Requirements

### Per-Platform Test Coverage
- [ ] Windows 10/11 (WinRT Toast)
- [ ] Windows 8.1 (Shell_NotifyIcon fallback)
- [ ] Ubuntu 22.04 (GNOME Shell)
- [ ] Ubuntu 22.04 (Dunst via Docker)
- [ ] Fedora (GNOME Shell)
- [ ] Arch Linux (Mako)
- [ ] KDE Plasma
- [ ] XFCE4
- [ ] macOS 10.14+ (UNUserNotificationCenter)

### Feature Test Matrix
For each platform, verify:
- Basic notification appears
- Title and message display correctly
- Icons render properly
- Urgency affects presentation
- Timeouts work as expected
- Action buttons function (where supported)
- Sound plays or mutes correctly
- Errors return meaningful messages
- Memory cleanup (no leaks)
- Performance meets targets (<50ms)

---

## Known Issues & Blockers

### Windows
- **First-run delay**: Shortcut creation adds ~100ms on first notification.
- **No native COM activation**: Cannot handle toast clicks/dismissals without implementing COM activation handler.
- ~~**PowerShell dependency**~~: **RESOLVED** - Now uses direct WinRT COM calls. PowerShell is kept as fallback only.

### Linux
- **Zero-dependency goal**: Need to implement D-Bus protocol directly or dynamically load libdbus-1.so.
- **Testing complexity**: Requires X11/Wayland environment with notification daemon running.
- **Daemon variations**: Behavior differs between Dunst, Mako, notify-osd, desktop environments.

### macOS
- ~~**No macOS development environment**~~: **RESOLVED** - Implemented and tested on macOS 26.0.1 (Tahoe).
- ~~**Objective-C bridge**~~: **RESOLVED** - Custom objc.zig implementation (~170 lines) with zero external dependencies.
- ~~**Authorization flow**~~: **RESOLVED** - Proper requestAuthorizationWithOptions:completionHandler: with block-based callback.
- ~~**Code signing**~~: **RESOLVED** - Ad-hoc signing automated in build.zig.
- **Bundle-context testing**: Tests must run from within .app bundle (implemented via custom build.zig logic).

---

## Dependencies & External Tools

### Windows
- **Required:** Windows SDK headers (GUID definitions, COM interfaces)
- **Runtime:** ole32.dll, shell32.dll, combase.dll (dynamically loaded)
- **Optional:** PowerShell 5.1+ (fallback only), Windows 10 SDK for native WinRT headers

### Linux
- **Required:** D-Bus protocol specification
- **Runtime:** D-Bus session bus daemon, notification daemon (dunst/mako/notify-osd/etc.)
- **Optional:** libdbus-1.so (if not implementing protocol directly)

### macOS
- **Required:** macOS SDK (Foundation, CoreFoundation, AppKit, UserNotifications frameworks)
- **Runtime:** macOS 10.12+ (10.14+ recommended for modern API), Objective-C runtime (libobjc)
- **Development:** Xcode Command Line Tools (provides frameworks and code signing tools)
- **Build:** Ad-hoc code signing via `codesign` (automatic in build.zig)
- **Zero External Dependencies:** Custom objc.zig implementation (no other external libraries required)

---

## Contributing Guidelines

When implementing backend features:

1. **Follow the platform abstraction contract** - All backends must implement the `Backend` interface in `platform/backend.zig`

2. **Maintain cross-platform parity** - Features should work consistently across platforms when possible

3. **Fail gracefully** - Unsupported features should return clear errors, not crash

4. **Test thoroughly** - Add integration tests for each new feature, use Docker for Linux testing

5. **Document limitations** - Update this roadmap with platform-specific constraints

6. **Keep it lightweight** - Every feature must maintain <50ms execution time and <5MB memory usage

7. **Zero dependencies** - Prefer dynamic loading or direct protocol implementation over linking libraries

---

## References

### Windows
- [Windows App SDK - Toast Notifications](https://docs.microsoft.com/windows/apps/design/shell/tiles-and-notifications/toast-schema)
- [Desktop Bridge - AppUserModelID](https://docs.microsoft.com/windows/win32/shell/appids)
- [Shell_NotifyIcon (Win32)](https://docs.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shell_notifyiconw)

### Linux
- [Desktop Notifications Specification](https://specifications.freedesktop.org/notification-spec/latest/)
- [D-Bus Specification](https://dbus.freedesktop.org/doc/dbus-specification.html)

### macOS
- [UserNotifications Framework](https://developer.apple.com/documentation/usernotifications)

---

Last Updated: 2025-10-08
