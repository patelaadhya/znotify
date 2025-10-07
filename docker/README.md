# Docker Testing Environment

This directory contains Docker configuration for cross-platform Linux testing with D-Bus support.

## Files

- **linux-dbus.Dockerfile** - Ubuntu 22.04 container with D-Bus, Zig 0.15.1, and notification daemon
- **entrypoint.sh** - Startup script that initializes D-Bus daemon, Xvfb, and dunst
- **docker-compose.yml** - Service orchestration for test/bench/interactive modes

## Environment

The Docker container provides:
- **OS**: Ubuntu 22.04 LTS
- **Zig**: 0.15.1 (matching development environment)
- **D-Bus**: Session bus daemon on `unix:path=/var/run/dbus/session_bus_socket`
- **Display**: Xvfb headless X11 server on `:99`
- **Notification Daemon**: Dunst (lightweight, standards-compliant)

## Usage

### Build the image

```bash
# Linux/macOS
./scripts/build-docker.sh

# Windows (PowerShell)
.\scripts\build-docker.ps1
```

### Run tests

```bash
# Linux/macOS
./scripts/test-linux.sh test

# Windows (PowerShell)
.\scripts\test-linux.ps1 test
```

### Other commands

```bash
./scripts/test-linux.sh bench   # Run benchmarks
./scripts/test-linux.sh build   # Build project
./scripts/test-linux.sh shell   # Interactive shell
./scripts/test-linux.sh clean   # Remove images and volumes
```

## How It Works

1. **Build Phase**: Downloads Zig 0.15.1, installs D-Bus and notification tools
2. **Startup**: Entrypoint script starts D-Bus daemon, Xvfb, and dunst
3. **Execution**: Source code mounted from host, cache stored in Docker volume
4. **Testing**: Tests run against real D-Bus notification daemon

## Cache Strategy

Build artifacts are stored in a Docker volume (`/tmp/zig-cache`) to avoid filesystem compatibility issues between Windows NTFS and Linux ext4.

## CI/CD Integration

GitHub Actions uses this Docker environment to test Linux D-Bus functionality on every commit. See `.github/workflows/test.yml`.
