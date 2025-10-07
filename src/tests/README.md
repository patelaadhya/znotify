# Test Organization

This directory contains modular test files for the znotify project.

## Structure

```
src/
├── tests.zig                      # Core tests (notification, CLI, validation, errors)
└── tests/
    ├── README.md                  # This file
    ├── linux_backend_test.zig     # Linux D-Bus backend tests
    └── windows_backend_test.zig   # Windows WinRT backend tests
```

## Test Categories

### Core Tests (`tests.zig`)
Tests for platform-agnostic functionality:
- Notification data structures
- CLI argument parsing
- Input validation and escaping
- Error handling
- Platform detection
- Terminal backend
- Generic backend creation

### Platform-Specific Tests

#### Linux Backend Tests (`linux_backend_test.zig`)
- D-Bus connection establishment
- Notification sending and closing
- GetCapabilities parsing
- Urgency level mapping (low/normal/critical)
- Timeout handling (default, timed, persistent)

#### Windows Backend Tests (`windows_backend_test.zig`)
- COM initialization
- WinRT Toast notification sending
- Toast XML generation
- XML escaping and sanitization
- Urgency-based audio selection

## Running Tests

```bash
# Run all tests
zig build test

# Run with specific optimization
zig build test -Doptimize=ReleaseSafe

# Platform-specific tests are automatically skipped on non-matching platforms
```

## Adding New Tests

### For Core Functionality
Add tests directly to `src/tests.zig`

### For Platform-Specific Features

1. **Linux**: Add to `linux_backend_test.zig`
2. **Windows**: Add to `windows_backend_test.zig`
3. **macOS**: Create `macos_backend_test.zig` and import in `tests.zig`

### Test Template

```zig
test "Feature description" {
    // Skip on non-matching platforms
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Initialize backend
    var backend = try linux.LinuxBackend.init(allocator);
    defer backend.deinit();

    // Skip if backend unavailable (e.g., no D-Bus)
    if (!backend.isAvailable()) {
        return error.SkipZigTest;
    }

    // Test implementation
    // ...
}
```

## Test Conventions

1. **Skip Non-Applicable Platforms**: Use `if (builtin.os.tag != .platform) return error.SkipZigTest;`
2. **Check Backend Availability**: Always check `isAvailable()` before running platform tests
3. **Clean Up Resources**: Use `defer` for cleanup (backend.deinit(), allocator.free())
4. **Short-Lived Notifications**: Use brief timeouts (500-1000ms) to avoid flooding notification daemon
5. **Close Notifications**: Call `backend.close(id)` after testing to clean up

## CI/CD Integration

GitHub Actions runs tests on all three platforms:
- Linux: Native + Docker (with D-Bus)
- Windows: Native
- macOS: Native (when available)

Platform-specific tests automatically skip on non-matching platforms.
