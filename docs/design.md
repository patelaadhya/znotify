# ZNotify Design Document
## Cross-Platform Desktop Notification Utility

**Version**: 1.0.0  
**Date**: October 2025  
**Status**: Design Phase

---

## 1. Executive Summary

ZNotify is a lightweight, cross-platform command-line utility for displaying desktop notifications, written in Zig. It serves as a modern alternative to traditional notification tools like `notify-send`, providing zero-dependency operation, minimal resource usage, and consistent behavior across Windows, Linux, and macOS.

### Key Objectives
- **Cross-platform compatibility** without external runtime dependencies
- **Minimal binary size** (target: <500KB per platform)
- **Fast execution** (target: <50ms to display notification)
- **Simple, intuitive CLI** compatible with existing notify-send scripts
- **Robust error handling** with clear user feedback
- **Production-grade reliability** suitable for automation and scripting

---

## 2. Technical Architecture

### 2.1 System Architecture

```
┌─────────────────────────────────────────────┐
│             CLI Interface Layer              │
│         (Argument Parser & Validator)        │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│           Core Notification Engine           │
│     (Platform-agnostic business logic)       │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│      Platform Abstraction Layer (PAL)        │
├──────────┬──────────────┬───────────────────┤
│  Windows │    Linux     │      macOS        │
│   API    │  (D-Bus)     │  (Foundation)     │
└──────────┴──────────────┴───────────────────┘
```

### 2.2 Component Breakdown

#### 2.2.1 CLI Interface Layer
- **Argument Parser**: Custom zero-allocation parser optimized for performance
- **Validator**: Input sanitization and validation
- **Help System**: Built-in documentation and usage examples

#### 2.2.2 Core Engine
- **Notification Manager**: Handles notification lifecycle
- **Queue Manager**: Optional notification queuing for rate limiting
- **Configuration Loader**: Reads optional config files

#### 2.2.3 Platform Abstraction Layer
- **Windows Backend**: Direct Win32 API or WinRT
- **Linux Backend**: D-Bus interface to notification daemon
- **macOS Backend**: NSUserNotification or UserNotifications framework

---

## 3. Detailed Design Specifications

### 3.1 Command-Line Interface

```bash
# Basic usage
znotify "Title" "Message body"

# Full syntax
znotify [OPTIONS] <title> [message]

# Options
-t, --timeout <ms>      Notification display time (0 = persistent)
-u, --urgency <level>   low|normal|critical
-i, --icon <type>       info|warning|error|<path>
-c, --category <cat>    Notification category
-a, --app-name <name>   Application name
-h, --hint <key:value>  Platform-specific hints
-r, --replace-id <id>   Replace existing notification
-p, --print-id          Print notification ID
-w, --wait              Wait for user interaction
-s, --sound <name>      Play sound (platform-specific)
-v, --version           Show version
    --help              Show help
    --config <file>     Use config file
    --dry-run          Validate without sending
```

### 3.2 Data Structures

```zig
// Core notification structure
pub const Notification = struct {
    // Required fields
    title: []const u8,
    message: []const u8,
    
    // Optional fields with defaults
    urgency: Urgency = .normal,
    timeout_ms: ?u32 = 5000,
    icon: Icon = .none,
    category: ?[]const u8 = null,
    app_name: []const u8 = "znotify",
    replace_id: ?u32 = null,
    
    // Platform-specific hints
    hints: HashMap([]const u8, Value),
    
    // Callbacks
    on_click: ?*const fn() void = null,
    on_close: ?*const fn(CloseReason) void = null,
    on_timeout: ?*const fn() void = null,
};

pub const Urgency = enum(u8) {
    low = 0,
    normal = 1,
    critical = 2,
};

pub const Icon = union(enum) {
    none,
    builtin: BuiltinIcon,
    file_path: []const u8,
    url: []const u8,
    data: IconData,
};

pub const BuiltinIcon = enum {
    info,
    warning,
    error,
    question,
    // Platform-specific mappings
};

pub const IconData = struct {
    format: ImageFormat,
    data: []const u8,
    width: u32,
    height: u32,
};

pub const CloseReason = enum {
    expired,
    dismissed,
    closed_by_app,
    undefined,
};
```

### 3.3 Platform-Specific Implementation

#### 3.3.1 Windows Implementation

```zig
// Windows notification backend using WinRT
pub const WindowsBackend = struct {
    toast_notifier: *IToastNotifier,
    
    pub fn init(allocator: Allocator) !WindowsBackend {
        // Initialize Windows Runtime
        // Create toast notifier
    }
    
    pub fn send(self: *WindowsBackend, notif: Notification) !u32 {
        // Create XML template
        // Set text, images, sounds
        // Show toast notification
        // Return notification ID
    }
    
    pub fn close(self: *WindowsBackend, id: u32) !void {
        // Remove notification by ID
    }
};

// Alternative: Win32 Shell_NotifyIcon for compatibility
pub const Win32Backend = struct {
    hwnd: HWND,
    notify_icon_data: NOTIFYICONDATA,
    
    pub fn init(allocator: Allocator) !Win32Backend {
        // Create hidden window
        // Initialize NOTIFYICONDATA
    }
    
    pub fn send(self: *Win32Backend, notif: Notification) !u32 {
        // Use Shell_NotifyIcon
        // Handle balloon notifications
    }
};
```

#### 3.3.2 Linux Implementation

```zig
// Linux notification using D-Bus
pub const LinuxBackend = struct {
    connection: *DBusConnection,
    
    pub fn init(allocator: Allocator) !LinuxBackend {
        // Connect to session bus
        // Verify notification service exists
    }
    
    pub fn send(self: *LinuxBackend, notif: Notification) !u32 {
        // Call org.freedesktop.Notifications.Notify
        // Handle response
        // Return notification ID
    }
    
    pub fn getCapabilities(self: *LinuxBackend) ![]const u8 {
        // Query server capabilities
    }
};

// Fallback: Direct libnotify if available
pub const LibnotifyBackend = struct {
    // Implementation using libnotify C library
};
```

#### 3.3.3 macOS Implementation

```zig
// macOS using Objective-C runtime
pub const MacOSBackend = struct {
    user_notification_center: *anyopaque,
    
    pub fn init(allocator: Allocator) !MacOSBackend {
        // Get NSUserNotificationCenter instance
        // Set delegate if needed
    }
    
    pub fn send(self: *MacOSBackend, notif: Notification) !u32 {
        // Create NSUserNotification
        // Set properties
        // Deliver notification
    }
};

// Alternative: osascript fallback
pub const OsascriptBackend = struct {
    pub fn send(notif: Notification) !void {
        // Execute osascript command
        // Handle AppleScript display notification
    }
};
```

### 3.4 Configuration File Format

```toml
# ~/.config/znotify/config.toml

[defaults]
timeout = 5000
urgency = "normal"
app_name = "ZNotify"
sound = true

[icons]
# Icon theme or path mappings
info = "/usr/share/icons/info.png"
warning = "/usr/share/icons/warning.png"
error = "/usr/share/icons/error.png"

[platform.windows]
use_action_center = true
sound_file = "C:\\Windows\\Media\\notify.wav"

[platform.linux]
use_fallback = false
notification_daemon = "auto"  # auto|dunst|mako|notify-osd

[platform.macos]
use_notification_center = true
bundle_identifier = "com.znotify.cli"
```

---

## 4. Error Handling Strategy

### 4.1 Error Categories

```zig
pub const ZNotifyError = error{
    // Initialization errors
    PlatformNotSupported,
    BackendInitFailed,
    NoNotificationService,
    
    // Input errors
    InvalidArgument,
    MissingRequiredField,
    InvalidIconPath,
    InvalidTimeout,
    
    // Runtime errors
    NotificationFailed,
    QueueFull,
    ServiceUnavailable,
    PermissionDenied,
    
    // Platform-specific
    DBusConnectionFailed,
    WindowsRuntimeError,
    MacOSAuthorizationDenied,
};

// Error handling pattern
pub fn handleError(err: ZNotifyError) void {
    const stderr = std.io.getStdErr().writer();
    switch (err) {
        .PlatformNotSupported => {
            stderr.print("Error: Platform not supported\n", .{}) catch {};
            std.process.exit(1);
        },
        .InvalidArgument => |arg| {
            stderr.print("Error: Invalid argument: {s}\n", .{arg}) catch {};
            std.process.exit(2);
        },
        // ... handle each error type
    }
}
```

### 4.2 Fallback Mechanisms

1. **Platform Detection Fallback**
   - Try primary backend → secondary backend → terminal output
   
2. **Icon Loading Fallback**
   - Custom icon → theme icon → builtin icon → no icon
   
3. **Notification Delivery Fallback**
   - Native API → D-Bus → libnotify → terminal notification

---

## 5. Testing Strategy

### 5.1 Unit Tests

```zig
test "argument parser handles all options" {
    const args = [_][]const u8{ "-t", "3000", "-u", "critical", "Title", "Message" };
    const config = try parseArgs(args);
    try expect(config.timeout == 3000);
    try expect(config.urgency == .critical);
}

test "notification builder creates valid structure" {
    const notif = try NotificationBuilder.init()
        .setTitle("Test")
        .setMessage("Message")
        .setTimeout(1000)
        .build();
    try expect(notif.timeout_ms == 1000);
}
```

### 5.2 Integration Tests

```zig
test "windows backend sends notification" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    
    const backend = try WindowsBackend.init(testing.allocator);
    defer backend.deinit();
    
    const id = try backend.send(.{
        .title = "Test",
        .message = "Integration test",
    });
    try expect(id > 0);
}
```

### 5.3 Platform-Specific Tests

- **Windows**: Test WinRT and Win32 backends
- **Linux**: Test with different notification daemons
- **macOS**: Test authorization and delivery

### 5.4 Performance Tests

```zig
test "notification sends within 50ms" {
    const start = std.time.milliTimestamp();
    try sendNotification(.{ .title = "Perf", .message = "Test" });
    const elapsed = std.time.milliTimestamp() - start;
    try expect(elapsed < 50);
}
```

---

## 6. Build Configuration

### 6.1 Build Script (build.zig)

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const exe = b.addExecutable(.{
        .name = "znotify",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    // Platform-specific configuration
    switch (target.getOsTag()) {
        .windows => {
            exe.linkSystemLibrary("ole32");
            exe.linkSystemLibrary("shell32");
            exe.linkSystemLibrary("user32");
            exe.subsystem = .Console;
        },
        .linux => {
            exe.linkSystemLibrary("dbus-1");
            exe.linkSystemLibrary("c");
        },
        .macos => {
            exe.linkFramework("Foundation");
            exe.linkFramework("AppKit");
            exe.linkSystemLibrary("objc");
        },
        else => {},
    }
    
    // Optional features
    const enable_config = b.option(bool, "config", "Enable config file support") orelse true;
    const enable_sound = b.option(bool, "sound", "Enable sound support") orelse true;
    
    const options = b.addOptions();
    options.addOption(bool, "enable_config", enable_config);
    options.addOption(bool, "enable_sound", enable_sound);
    exe.addOptions("build_options", options);
    
    b.installArtifact(exe);
    
    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    
    // Benchmarks
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = .{ .path = "src/bench.zig" },
        .target = target,
        .optimize = .ReleaseFast,
    });
    
    const bench_cmd = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&bench_cmd.step);
}
```

### 6.2 Release Configuration

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            target: x86_64-linux-gnu
          - os: windows-latest
            target: x86_64-windows
          - os: macos-latest
            target: x86_64-macos
          - os: macos-latest
            target: aarch64-macos
    
    runs-on: ${{ matrix.os }}
    
    steps:
      - uses: actions/checkout@v3
      - uses: goto-bus-stop/setup-zig@v2
      
      - name: Build
        run: |
          zig build -Doptimize=ReleaseSafe -Dtarget=${{ matrix.target }}
          
      - name: Package
        run: |
          tar czf znotify-${{ matrix.target }}.tar.gz zig-out/bin/znotify*
          
      - name: Upload
        uses: actions/upload-artifact@v3
        with:
          name: znotify-${{ matrix.target }}
          path: znotify-${{ matrix.target }}.tar.gz
```

---

## 7. Security Considerations

### 7.1 Input Validation
- **Command Injection Prevention**: Sanitize all user inputs
- **Path Traversal Prevention**: Validate icon paths
- **XML/HTML Injection**: Escape special characters in messages
- **Size Limits**: Cap message and title lengths

### 7.2 Platform Security

#### Windows
- Sign binaries with code certificate
- Request appropriate UAC level (asInvoker)
- Validate COM/WinRT initialization

#### Linux
- Validate D-Bus message format
- Check notification daemon identity
- Respect SELinux/AppArmor policies

#### macOS
- Handle notification authorization properly
- Sign with Developer ID
- Respect sandboxing requirements

### 7.3 Privacy
- No telemetry or analytics
- No network connections except for icon URLs (optional)
- No persistent storage of notification content
- Clear memory after notification display

---

## 8. Performance Requirements

### 8.1 Metrics

| Metric | Target | Maximum |
|--------|--------|---------|
| Startup time | < 10ms | 50ms |
| Memory usage | < 5MB | 10MB |
| CPU usage | < 1% | 5% |
| Binary size | < 500KB | 1MB |
| Notification display | < 50ms | 100ms |

### 8.2 Optimization Strategies

1. **Zero Allocation Where Possible**
   - Stack-based buffers for small strings
   - Pre-allocated notification queue

2. **Lazy Loading**
   - Load platform backends on-demand
   - Defer config file parsing

3. **Compile-Time Optimization**
   - Use comptime for known values
   - Eliminate dead code per platform

---

## 9. Compatibility Matrix

### 9.1 Operating System Support

| OS | Minimum Version | Recommended | Notes |
|----|-----------------|-------------|-------|
| Windows | Windows 8.1 | Windows 10+ | WinRT for modern, Win32 fallback |
| Linux | Kernel 3.10 | Kernel 5.0+ | D-Bus 1.6+ required |
| macOS | 10.12 Sierra | 11.0 Big Sur+ | UserNotifications framework |
| FreeBSD | 12.0 | 13.0+ | Linux compatibility layer |

### 9.2 Architecture Support

- x86_64 (primary)
- aarch64 (ARM64)
- x86 (32-bit, limited support)
- RISC-V (experimental)

### 9.3 Notification Service Compatibility

#### Linux
- GNOME Shell
- KDE Plasma
- Dunst
- Mako (Wayland)
- notify-osd
- XFCE4-notifyd

#### Windows
- Action Center (Windows 10+)
- System Tray (fallback)

#### macOS
- Notification Center
- Growl (legacy, optional)

---

## 10. Project Structure

```
znotify/
├── build.zig
├── build.zig.zon           # Dependencies
├── LICENSE
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── API.md
│   ├── CONTRIBUTING.md
│   └── examples/
├── src/
│   ├── main.zig           # Entry point
│   ├── cli.zig            # Argument parsing
│   ├── core.zig           # Core logic
│   ├── notification.zig   # Data structures
│   ├── config.zig         # Configuration
│   ├── platform/
│   │   ├── backend.zig    # Interface
│   │   ├── windows.zig
│   │   ├── linux.zig
│   │   └── macos.zig
│   ├── utils/
│   │   ├── escaping.zig
│   │   └── validation.zig
│   └── tests/
│       ├── unit/
│       ├── integration/
│       └── bench.zig
├── assets/
│   ├── icons/
│   └── sounds/
└── examples/
    ├── basic.sh
    ├── advanced.sh
    └── integration.py
```

---

## 11. Deployment and Distribution

### 11.1 Package Formats

- **Binary releases**: GitHub Releases with pre-built binaries
- **Package managers**:
  - Homebrew (macOS/Linux)
  - Scoop/Chocolatey (Windows)
  - APT/YUM/Pacman (Linux)
  - Nix/Guix
- **Container**: Docker image for CI/CD usage

### 11.2 Installation Methods

```bash
# Homebrew
brew install znotify

# From source
git clone https://github.com/user/znotify
cd znotify
zig build -Doptimize=ReleaseSafe
sudo zig build install

# Binary download
curl -LO https://github.com/user/znotify/releases/latest/download/znotify-linux-x86_64
chmod +x znotify-linux-x86_64
sudo mv znotify-linux-x86_64 /usr/local/bin/znotify
```

---

## 12. Migration Path

### 12.1 From notify-send

```bash
# Compatibility wrapper
alias notify-send='znotify --compat'

# Automated script conversion
znotify --migrate-script old-script.sh > new-script.sh
```

### 12.2 API Compatibility Layer

```zig
// Compatible with common notify-send usage
pub fn compatMode(args: [][]const u8) !void {
    // Map notify-send args to znotify
    // -u urgency → --urgency
    // -t timeout (seconds) → --timeout (ms)
    // -i icon → --icon
}
```

---

## 13. Monitoring and Diagnostics

### 13.1 Debug Mode

```bash
# Verbose output
znotify --debug "Test" "Message"

# Output:
# [DEBUG] Platform: linux
# [DEBUG] Backend: DBus
# [DEBUG] Notification ID: 42
# [DEBUG] Delivery time: 23ms
```

### 13.2 Health Check

```bash
# System diagnostic
znotify --doctor

# Output:
# ✓ Platform supported: Linux 5.15
# ✓ Notification service: org.freedesktop.Notifications
# ✓ D-Bus connection: Active
# ✓ Icon theme: Adwaita
# ✓ Sound system: PulseAudio
```

---

## 14. Future Enhancements

### 14.1 Version 1.1 (Q2 2026)
- Action buttons support
- Progress bar notifications
- Notification history/log
- Remote notification support

### 14.2 Version 1.2 (Q4 2026)
- Plugin system for extensions
- Web API for remote notifications
- Notification templating engine
- Rich media support (GIFs, videos)

### 14.3 Version 2.0 (2027)
- GUI configuration tool
- Notification center replacement
- Cross-device synchronization
- End-to-end encryption for remote notifications

---

## 15. Success Metrics

### 15.1 Technical Metrics
- Binary size < 500KB achieved
- Startup time < 10ms on modern hardware
- Zero crashes in 1 million notifications
- 100% API compatibility with notify-send

### 15.2 Adoption Metrics
- 10,000+ GitHub stars within first year
- Included in major Linux distributions
- 50+ third-party integrations
- Active community with 100+ contributors

### 15.3 Quality Metrics
- > 90% test coverage
- A+ security audit rating
- < 24 hour critical bug fix turnaround
- Comprehensive documentation rated 9/10 by users

---

## Appendix A: API Reference

```zig
// Public API surface
pub const znotify = struct {
    // Core functions
    pub fn send(notification: Notification) !u32;
    pub fn cancel(id: u32) !void;
    pub fn update(id: u32, notification: Notification) !void;
    
    // Query functions
    pub fn getCapabilities() ![]const u8;
    pub fn getServerInfo() !ServerInfo;
    pub fn isSupported() bool;
    
    // Configuration
    pub fn loadConfig(path: []const u8) !Config;
    pub fn setDefaults(config: Config) void;
    
    // Utilities
    pub fn escapeMarkup(text: []const u8) []const u8;
    pub fn validateIcon(path: []const u8) !void;
};
```

---

## Appendix B: Example Scripts

### Basic Usage
```bash
#!/bin/bash
# Simple notification
znotify "Build Complete" "Your project has been built successfully"

# With timeout and icon
znotify -t 3000 -i success "Deployed" "Application deployed to production"

# Critical notification
znotify -u critical -i error "Disk Full" "System disk is 95% full"
```

### Advanced Integration
```python
#!/usr/bin/env python3
import subprocess
import json

class ZNotify:
    @staticmethod
    def send(title, message, **kwargs):
        cmd = ["znotify"]
        for key, value in kwargs.items():
            cmd.extend([f"--{key}", str(value)])
        cmd.extend([title, message])
        result = subprocess.run(cmd, capture_output=True)
        return result.returncode == 0
    
    @staticmethod
    def send_progress(title, message, progress):
        return ZNotify.send(
            title, 
            message,
            hint=f"value:{progress}",
            category="transfer"
        )

# Usage
notifier = ZNotify()
notifier.send("Hello", "World", timeout=5000, icon="info")
```

---

## Appendix C: Troubleshooting Guide

### Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| No notification appears | Service not running | Check with `znotify --doctor` |
| Icon not showing | Invalid path/format | Use `znotify --validate-icon <path>` |
| Notification cut off | Text too long | Increase timeout or reduce message |
| Permission denied | Missing authorization | Run `znotify --request-permission` |
| Crashes on startup | Incompatible platform | Check compatibility matrix |

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2025-10-06 | Design Team | Initial design document |

---

*This design document serves as the authoritative guide for implementing ZNotify. All implementation decisions should reference this document, and any deviations should be documented and justified.*