# Test znotify in Linux Docker container

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Set-Location $ProjectRoot

# Colors for output
function Write-Red($message) {
    Write-Host $message -ForegroundColor Red
}

function Write-Green($message) {
    Write-Host $message -ForegroundColor Green
}

function Write-Yellow($message) {
    Write-Host $message -ForegroundColor Yellow
}

Write-Green "ZNotify Linux Testing"
Write-Host "======================================"

# Check if Docker is available
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Red "Error: Docker is not installed or not in PATH"
    exit 1
}

# Parse command line arguments
$Command = if ($args.Count -gt 0) { $args[0] } else { "test" }

switch ($Command) {
    "test" {
        Write-Yellow "Running tests in Linux container..."
        docker compose -f docker/docker-compose.yml run --rm test
    }
    "bench" {
        Write-Yellow "Running benchmarks in Linux container..."
        docker compose -f docker/docker-compose.yml run --rm bench
    }
    "shell" {
        Write-Yellow "Starting interactive shell in Linux container..."
        docker compose -f docker/docker-compose.yml run --rm linux-test
    }
    "build" {
        Write-Yellow "Building in Linux container..."
        docker compose -f docker/docker-compose.yml run --rm linux-test zig build --cache-dir /tmp/zig-cache
    }
    "clean" {
        Write-Yellow "Cleaning up Docker resources..."
        docker compose -f docker/docker-compose.yml down -v
        docker rmi znotify-linux-test:latest 2>$null
        Write-Green "Cleanup complete"
    }
    default {
        Write-Host "Usage: .\scripts\test-linux.ps1 {test|bench|shell|build|clean}"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  test   - Run tests in Linux container (default)"
        Write-Host "  bench  - Run benchmarks in Linux container"
        Write-Host "  shell  - Start interactive shell in Linux container"
        Write-Host "  build  - Build project in Linux container"
        Write-Host "  clean  - Remove Docker images and volumes"
        exit 1
    }
}

Write-Green "Done!"
