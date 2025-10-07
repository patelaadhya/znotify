# Build and Test Scripts

This directory contains cross-platform scripts for building and testing znotify.

## Scripts

### build-docker.sh / build-docker.ps1

Builds the Docker image for Linux testing.

**Usage:**
```bash
# Linux/macOS
./scripts/build-docker.sh          # Clean build (no cache)
./scripts/build-docker.sh --cache  # Build with cache (faster)

# Windows (PowerShell)
.\scripts\build-docker.ps1          # Clean build (no cache)
.\scripts\build-docker.ps1 --cache  # Build with cache (faster)
```

**What it does:**
- Builds Ubuntu 22.04 container with D-Bus, Zig 0.15.1, and notification daemon
- Uses docker-compose.yml configuration
- Shows available images after build

### test-linux.sh / test-linux.ps1

Runs tests, benchmarks, or opens interactive shell in Linux Docker container.

**Usage:**
```bash
# Linux/macOS
./scripts/test-linux.sh test   # Run tests
./scripts/test-linux.sh bench  # Run benchmarks
./scripts/test-linux.sh build  # Build project
./scripts/test-linux.sh shell  # Interactive shell
./scripts/test-linux.sh clean  # Remove images and volumes

# Windows (PowerShell)
.\scripts\test-linux.ps1 test   # Run tests
.\scripts\test-linux.ps1 bench  # Run benchmarks
.\scripts\test-linux.ps1 build  # Build project
.\scripts\test-linux.ps1 shell  # Interactive shell
.\scripts\test-linux.ps1 clean  # Remove images and volumes
```

**What it does:**
- Validates Docker is installed
- Runs specified command in Docker container
- Mounts source code for live updates
- Uses container-local cache for performance

## Requirements

- Docker Engine 20.10+ or Docker Desktop
- docker-compose v2.0+ (typically bundled with Docker)

## Platform Support

Both bash and PowerShell versions provide identical functionality:
- **bash**: Linux, macOS, WSL
- **PowerShell**: Windows (PowerShell 5.1+, PowerShell Core 7+)

## Troubleshooting

**"Docker is not installed or not in PATH"**
- Install Docker Desktop (Windows/macOS) or Docker Engine (Linux)
- Ensure `docker` command is in your PATH

**Permission errors**
- Linux/macOS: Add user to `docker` group
- Windows: Ensure Docker Desktop is running

**Slow builds**
- Use `--cache` flag on subsequent builds
- Docker will reuse layers when possible
