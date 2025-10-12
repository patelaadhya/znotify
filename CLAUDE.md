# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZNotify is a lightweight, cross-platform command-line utility for desktop notifications written in Zig. It serves as a modern alternative to `notify-send`, providing zero-dependency operation, minimal resource usage (<500KB binary, <50ms execution), and consistent behavior across Windows, Linux, and macOS.

## Build Commands

### Development
```bash
# Build the project
zig build

# Run the executable
zig build run

# Run with arguments
zig build run -- "Title" "Message"

# Run tests
zig build test

# Build with debug output
zig build -Ddebug=true

# Build without config file support
zig build -Dconfig=false
```

### Cross-Platform Builds
```bash
# Windows (x86_64)
zig build -Dtarget=x86_64-windows

# Linux (x86_64)
zig build -Dtarget=x86_64-linux-gnu

# macOS (x86_64)
zig build -Dtarget=x86_64-macos

# macOS (ARM64)
zig build -Dtarget=aarch64-macos
```

### Release Builds
```bash
# Optimized for safety and performance
zig build -Doptimize=ReleaseSafe

# Maximum performance
zig build -Doptimize=ReleaseFast

# Minimum binary size
zig build -Doptimize=ReleaseSmall
```

## Architecture

### High-Level Structure

```
CLI Layer (cli.zig)
    ↓
Core Engine (core.zig, notification.zig)
    ↓
Platform Abstraction Layer (platform/backend.zig)
    ↓
Platform Implementations (platform/windows.zig, linux.zig, macos.zig)
```

### Key Components

- **CLI Layer**: Argument parser, input validation, help system
- **Core Engine**: Notification manager, queue manager, configuration loader
- **Platform Abstraction**: Unified interface for all OS-specific backends
- **Platform Implementations**:
  - Windows: WinRT Toast API (fallback: Win32 Shell_NotifyIcon)
  - Linux: D-Bus interface to `org.freedesktop.Notifications`
  - macOS: UserNotifications framework (requires macOS 10.14+)

### Data Flow

1. CLI parses arguments → validates input → creates Notification struct
2. Core engine loads config → applies defaults → prepares notification
3. Platform layer detects OS → initializes appropriate backend
4. Backend sends notification via OS-specific API → returns notification ID

## Implementation Workflow

This project follows a structured implementation guide in `docs/guide.md`. Use the custom slash commands to manage development:

### Custom Slash Commands

- `/next` - Shows the next chunk to implement from the guide
- `/proceed` - Implements the next chunk automatically
- `/progress` - Reports current progress and completion status
- `/commit [message]` - Builds, tests, and commits with conventional commit format

### Typical Development Flow

```bash
# 1. Check what's next
/next

# 2. Implement the next chunk
/proceed

# 3. Verify and commit
/commit
```

## Code Organization

### Directory Structure

```
src/
├── main.zig              # Entry point, CLI orchestration
├── cli.zig               # Argument parsing and validation
├── core.zig              # Core notification engine
├── notification.zig      # Data structures (Notification, Urgency, Icon)
├── errors.zig            # Error types and handling
├── config.zig            # Configuration file parsing
├── platform/
│   ├── backend.zig       # Platform abstraction interface
│   ├── windows.zig       # Windows WinRT/Win32 implementation
│   ├── linux.zig         # Linux D-Bus implementation
│   ├── macos.zig         # macOS Foundation framework implementation
│   └── objc.zig          # Custom Objective-C runtime bindings (macOS only)
├── utils/
│   ├── escaping.zig      # HTML/XML escaping for safety
│   └── validation.zig    # Input validation utilities
└── tests/
    ├── unit/             # Unit tests per component
    ├── integration/      # Cross-platform integration tests
    └── bench.zig         # Performance benchmarks
```

## Testing Strategy

### Unit Tests
- Located in `src/tests.zig` and `src/tests/unit/`
- Test individual functions and data structures
- Target: >90% code coverage
- Run with: `zig build test`

### Platform-Specific Tests
- Use `if (builtin.os.tag != .windows) return error.SkipZigTest;` to conditionally skip
- Test each backend implementation separately
- Verify fallback mechanisms work correctly

### Performance Tests
- Located in `src/tests/bench.zig`
- Critical metrics: startup <10ms, notification display <50ms, memory <5MB
- Run with: `zig build bench`

## Docker Testing Environment

### Overview
Docker-based Linux testing environment with D-Bus support, enabling cross-platform testing from any development machine (Windows, macOS, or Linux).

### Building Docker Images
```bash
# Linux/macOS
./scripts/build-docker.sh          # Build without cache (clean build)
./scripts/build-docker.sh --cache  # Build with cache (faster)

# Windows (PowerShell)
.\scripts\build-docker.ps1          # Build without cache (clean build)
.\scripts\build-docker.ps1 --cache  # Build with cache (faster)
```

### Running Tests in Docker
```bash
# Linux/macOS
./scripts/test-linux.sh test   # Run all tests
./scripts/test-linux.sh bench  # Run benchmarks
./scripts/test-linux.sh build  # Build project
./scripts/test-linux.sh shell  # Interactive shell for debugging
./scripts/test-linux.sh clean  # Clean up Docker resources

# Windows (PowerShell)
.\scripts\test-linux.ps1 test   # Run all tests
.\scripts\test-linux.ps1 bench  # Run benchmarks
.\scripts\test-linux.ps1 build  # Build project
.\scripts\test-linux.ps1 shell  # Interactive shell for debugging
.\scripts\test-linux.ps1 clean  # Clean up Docker resources
```

### Docker Environment Details
- **Base**: Ubuntu 22.04
- **Zig**: 0.15.1 (matches development environment)
- **D-Bus**: Session bus daemon with auto-start
- **Notification Daemon**: Dunst (lightweight notification daemon)
- **Display**: Xvfb (headless X11 server on :99)
- **Volumes**: Source code mounted at `/workspace`

### CI/CD Integration
GitHub Actions workflow (`.github/workflows/test.yml`) runs:
- Native tests on Linux, Windows, and macOS
- Docker-based tests with D-Bus integration on Linux
- Benchmarks on all platforms

### Docker Compose Services
- `linux-test`: Interactive development environment
- `test`: One-shot test execution
- `bench`: One-shot benchmark execution

## Platform-Specific Implementation Notes

### Windows
- **Status**: ✅ **IMPLEMENTED** - Core functionality working with direct COM
- Primary: WinRT Toast API for Windows 10+
- **Direct WinRT COM Implementation**:
  - Dynamically loads combase.dll at runtime (WindowsCreateString, WindowsDeleteString, RoGetActivationFactory)
  - Direct COM interface calls to Windows.Data.Xml.Dom.XmlDocument
  - Direct COM interface calls to Windows.UI.Notifications.ToastNotification
  - Direct COM interface calls to Windows.UI.Notifications.ToastNotificationManager
  - PowerShell fallback for compatibility (automatic on COM failure)
  - Performance: <10ms per notification (vs 30-50ms with PowerShell)
- Start Menu shortcut creation with AppUserModelID (required for unpackaged apps)
- Link libraries: `ole32`, `shell32`, `user32`
- Runtime libraries: `combase.dll` (dynamically loaded)
- Subsystem: `.Console`
- **Working Features**:
  - Toast notifications with title and message
  - Urgency mapping (audio and scenario attributes)
  - Timeout handling (auto-dismiss based on timeout_ms: <10s → "short", ≥10s → "long")
  - Action Center persistence
  - XML escaping for safety
- **TODO**:
  - Custom icon support
  - Action buttons with COM activation handler
  - Shell_NotifyIcon fallback for Windows 8.1

### Linux
- **Status**: ✅ **PHASE 3 COMPLETE** - ActionInvoked signal handler implemented
- Primary: D-Bus interface to notification daemon
- Protocol: `org.freedesktop.Notifications` specification
- Implementation: Pure Zig D-Bus binary protocol (zero dependencies)
- **Working Features**:
  - D-Bus connection via UNIX socket with EXTERNAL authentication
  - Hello() handshake for connection establishment
  - Basic notifications with title and message
  - Urgency levels (low/normal/critical) with proper hints encoding
  - Timeout handling (persistent, timed, default)
  - Notification ID tracking and return
  - Message filtering (handles signals vs method returns)
  - Icon support (theme names and file paths via -i/--icon option)
  - Notification updates via replaces_id (-r/--replace-id option)
  - GetCapabilities D-Bus method with capability checking helpers
  - Action buttons (--action <id> <label> CLI option, repeatable)
  - ActionInvoked signal handler with --wait mode (blocks until action clicked)
  - Modular test suite with comprehensive coverage
- Compatible with: GNOME, KDE, Dunst, Mako, notify-osd, XFCE4-notifyd
- **Note on Action Buttons**: Mako daemon uses CLI-based action invocation (`makoctl invoke`/`makoctl menu`) rather than visual buttons. GNOME, KDE, and Dunst show visual buttons.
- **Wait Mode Usage**:
  - `znotify "Title" "Message" --action "yes" "Yes" --action "no" "No" --wait` blocks until user clicks an action
  - `--wait-timeout=5000` waits max 5 seconds before timing out (returns exit code 1)
  - Prints the action key when clicked: `Action invoked: yes`
- **TODO (Phase 4)**:
  - Sound hints (sound-file, sound-name, suppress-sound)
  - Notification closure tracking (NotificationClosed signal)
- See `docs/backend-roadmap.md` for full implementation plan

### macOS
- **Status**: ✅ **IMPLEMENTED** - Core functionality working with modern API
- Requires: macOS 10.14+ (Mojave or later)
- Framework: UserNotifications (UNUserNotificationCenter)
- **Implementation Details**:
  - Dynamically detects macOS version (handles both 10.x and 11+ versioning)
  - **Custom Objective-C runtime bindings** (objc.zig) - zero external dependencies
  - Objective-C block support for completion handlers
  - Proper authorization request using requestAuthorizationWithOptions:completionHandler:
  - Direct UNUserNotificationCenter API calls
  - Requires proper app bundle structure (ZNotify.app with Info.plist)
  - Requires ad-hoc code signing for UserNotifications framework
  - CFRunLoop integration (0.2s minimum for banner display)
- Link frameworks: `Foundation`, `CoreFoundation`, `AppKit`, `UserNotifications`
- Link library: `objc` (C runtime only, no external dependencies)
- **Objective-C Interop** (src/platform/objc.zig ~170 lines):
  - Custom msgSend implementation with proper function type generation
  - Block literal support for completion handlers
  - Class and Object wrappers
  - Zero dependency on external libraries
- **Working Features**:
  - Notifications with title and message
  - Banner display and Notification Center integration
  - Proper authorization request with block-based completion handler
  - Authorization status tracking
  - Unique notification identifiers
  - Automatic API selection based on OS version
  - Bundle-context testing (tests run from within ZNotify.app/Contents/MacOS/)
  - Icon support (local file paths and builtin SF Symbols)
    - File path icons: Direct file usage (no copying, privacy-focused)
    - Builtin icons: SF Symbols (info, warning, error, question, success)
    - SF Symbols converted to PNG in /tmp (temporary, system-managed cleanup)
    - UNNotificationAttachment with thumbnail visibility control
- **Testing Infrastructure**:
  - Custom build.zig logic runs tests from within app bundle
  - Solves UNUserNotificationCenter requirement for valid bundle identifier
  - Industry best practice for testing framework APIs
  - Comprehensive test coverage including icon support tests
- **TODO (Phase 2)**:
  - Action buttons
  - Sound configuration
  - Urgency level mapping
  - Notification timeout handling

## Error Handling Philosophy

- Use Zig error unions (`!Type`) for all fallible operations
- Define errors in `src/errors.zig` with clear categories:
  - Initialization errors (platform not supported, backend init failed)
  - Input errors (invalid argument, missing field)
  - Runtime errors (notification failed, permission denied)
  - Platform-specific errors (DBus failed, Windows COM error)
- Always provide actionable error messages to users
- Implement fallback mechanisms where appropriate

## Performance Requirements

### Hard Targets
- Binary size: <500KB (target), <1MB (maximum)
- Startup time: <10ms (target), <50ms (maximum)
- Memory usage: <5MB (target), <10MB (maximum)
- Notification display: <50ms (target), <100ms (maximum)
- CPU usage: <1% (target), <5% (maximum)

### Optimization Strategies
- Use stack-based buffers for small strings (avoid heap allocations)
- Lazy load platform backends on-demand
- Use `comptime` for constants and known values
- Pre-allocate notification queue with fixed size
- Eliminate dead code per platform in release builds

## Configuration

### Config File Locations (in priority order)
1. Command-line `--config <file>`
2. Current directory: `./znotify.toml`
3. User config: `~/.config/znotify/config.toml` (Linux/macOS) or `%APPDATA%\znotify\config.toml` (Windows)
4. System config: `/etc/znotify/config.toml` (Linux/macOS) or `C:\ProgramData\znotify\config.toml` (Windows)

### Config Format
- TOML format
- Sections: `[defaults]`, `[icons]`, `[platform.windows]`, `[platform.linux]`, `[platform.macos]`
- Override priority: CLI args > env vars > user config > system config

## Security Considerations

- **Input validation**: Always sanitize user input to prevent injection
- **Path validation**: Check for path traversal in icon paths
- **XML/HTML escaping**: Escape notification content to prevent markup injection
- **Memory safety**: Leverage Zig's compile-time safety features
- **No telemetry**: Never collect or transmit user data
- **No network**: No network connections except optional icon URL loading (with user consent)

## Compatibility & Backward Compatibility

### OS Support Matrix
- Windows: 8.1+ (primary: 10+)
- Linux: Kernel 3.10+ (D-Bus 1.6+)
- macOS: 10.12+ (primary: 11.0+)
- FreeBSD: 12.0+ (Linux compat layer)

### Architecture Support
- Primary: x86_64, aarch64 (ARM64)
- Limited: x86 (32-bit)
- Experimental: RISC-V

### notify-send Compatibility
- Implement `--compat` mode for drop-in replacement
- Map common arguments: `-u urgency`, `-t timeout`, `-i icon`
- Support symlink as `notify-send`
- Provide migration script for automated conversion

## Development Environment

### Required Tools
- Zig 0.11.0 or higher
- Git 2.0+
- Platform-specific: Windows SDK, D-Bus development files (Linux), Xcode Command Line Tools (macOS)

### Optional Tools
- Make (build automation alternative)
- Docker (container testing)
- VS Code with Zig extension

### Recommended Setup
- Use `ReleaseSafe` optimization for development to catch runtime errors
- Enable `--debug` build option for verbose output during development
- Test on all three platforms before committing platform layer changes

## Coding Standards

### Zig-Specific
- Follow Zig standard library conventions
- Use explicit error handling (avoid `catch unreachable` unless truly unreachable)
- Prefer stack allocation over heap when size is known and reasonable
- Use `defer` for cleanup to ensure resources are freed
- Document public APIs with doc comments (`///`)

### General
- Keep functions focused and small
- Meaningful variable names over comments
- Early returns to reduce nesting
- Write tests for all public APIs
- Benchmark performance-critical code paths

## Git Workflow

### Commit Message Format
Follow conventional commits:
- `feat:` - New feature
- `fix:` - Bug fix
- `refactor:` - Code refactoring
- `test:` - Add/update tests
- `docs:` - Documentation changes
- `perf:` - Performance improvements
- `chore:` - Build/tooling changes

### Branch Strategy
- `main` - stable, production-ready code
- Feature branches: `feature/<description>`
- Bug fix branches: `bugfix/<description>`

## Key Design Principles

1. **Zero Dependencies**: No runtime dependencies for core functionality
2. **Cross-Platform Parity**: Consistent behavior across all supported platforms
3. **Performance First**: Every feature must maintain <50ms execution time
4. **Privacy by Design**: No telemetry, no network calls, no data collection
5. **Backward Compatible**: Seamless migration from notify-send
6. **Developer Friendly**: Clear API, comprehensive docs, helpful error messages
