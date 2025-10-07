# Build Docker images for znotify testing

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Set-Location $ProjectRoot

# Colors for output
function Write-Green($message) {
    Write-Host $message -ForegroundColor Green
}

function Write-Yellow($message) {
    Write-Host $message -ForegroundColor Yellow
}

Write-Green "Building ZNotify Docker Images"
Write-Host "======================================"

# Parse command line arguments
$CacheFlag = if ($args.Count -gt 0) { $args[0] } else { "--no-cache" }

if ($CacheFlag -eq "--cache") {
    Write-Yellow "Building with cache..."
    $CacheArg = ""
} else {
    Write-Yellow "Building without cache (clean build)..."
    $CacheArg = "--no-cache"
}

# Build Linux testing image
Write-Host ""
Write-Yellow "Building Linux D-Bus testing image..."

if ($CacheArg -eq "") {
    docker compose -f docker/docker-compose.yml build linux-test
} else {
    docker compose -f docker/docker-compose.yml build $CacheArg linux-test
}

Write-Host ""
Write-Green "Build complete!"
Write-Host ""
Write-Host "Available images:"
docker images | Select-String "znotify"

Write-Host ""
Write-Host "Usage:"
Write-Host "  .\scripts\test-linux.ps1 test   - Run tests"
Write-Host "  .\scripts\test-linux.ps1 shell  - Interactive shell"
Write-Host "  .\scripts\test-linux.ps1 bench  - Run benchmarks"
