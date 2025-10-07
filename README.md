# znotify

A lightweight, cross-platform command-line utility for desktop notifications written in Zig.

## Features

- **Zero Dependencies**: Single static binary with no runtime dependencies
- **Cross-Platform**: Works on Windows, Linux, and macOS
- **Fast**: <50ms notification display, <500KB binary size
- **Privacy-First**: No telemetry, no network calls, no data collection
- **notify-send Compatible**: Drop-in replacement for notify-send

## Status

**In Development** - Not yet ready for production use

Currently implemented:
- Core notification data structures
- CLI argument parser
- Input validation and sanitization
- Error handling with user-friendly messages
- Performance benchmarks
- Docker-based testing infrastructure
- Platform abstraction layer
- Windows notifications (WinRT Toast API with COM integration)
  - Toast notifications with title and message
  - Start Menu shortcut creation with AppUserModelID
  - Urgency level mapping (audio and scenario)
  - Action Center integration

Coming soon:
- Linux notifications (D-Bus implementation)
- macOS notifications (UserNotifications framework)
- Custom icon support (all platforms)
- Action buttons (all platforms)
- Configuration file support
- Shell_NotifyIcon fallback (Windows 8.1)

## Building

### Requirements

- Zig 0.15.1 or higher
- Git 2.0+

### Build Commands

```bash
# Build the project
zig build

# Run tests
zig build test

# Run benchmarks
zig build bench

# Build release binary
zig build -Doptimize=ReleaseSafe
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

## Docker Testing

Test Linux D-Bus functionality on any platform:

```bash
# Build Docker image
./scripts/build-docker.sh          # Linux/macOS
.\scripts\build-docker.ps1          # Windows

# Run tests
./scripts/test-linux.sh test       # Linux/macOS
.\scripts\test-linux.ps1 test      # Windows
```

See [docker/README.md](docker/README.md) for details.

## Usage (Planned)

```bash
# Basic notification
znotify "Title" "Message"

# With urgency level
znotify "Warning" "Disk space low" -u critical

# With icon
znotify "Update Available" "Click to install" -i software-update

# Custom timeout
znotify "Auto-save" "Changes saved" -t 2000

# notify-send compatibility mode
znotify --compat -u low -i dialog-information "Info" "Operation complete"
```

## Architecture

```
CLI Layer (cli.zig)
    ↓
Core Engine (core.zig, notification.zig)
    ↓
Platform Abstraction Layer (platform/backend.zig)
    ↓
Platform Implementations
    ├── Windows: WinRT Toast API
    ├── Linux: D-Bus (org.freedesktop.Notifications)
    └── macOS: UserNotifications framework
```

## Performance Targets

- Binary size: <500KB (target), <1MB (maximum)
- Startup time: <10ms (target), <50ms (maximum)
- Memory usage: <5MB (target), <10MB (maximum)
- Notification display: <50ms (target), <100ms (maximum)

## Development

### Running Tests

```bash
# Unit tests
zig build test

# Benchmarks
zig build bench

# Linux integration tests (Docker)
./scripts/test-linux.sh test      # Linux/macOS
.\scripts\test-linux.ps1 test     # Windows
```

## License

MIT License - See [LICENSE](LICENSE) for details.
