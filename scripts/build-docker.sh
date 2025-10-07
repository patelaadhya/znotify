#!/bin/bash
# Build Docker images for znotify testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building ZNotify Docker Images${NC}"
echo "======================================"

# Parse command line arguments
CACHE_FLAG="${1:---no-cache}"

if [ "$CACHE_FLAG" = "--cache" ]; then
    echo -e "${YELLOW}Building with cache...${NC}"
    CACHE_ARG=""
else
    echo -e "${YELLOW}Building without cache (clean build)...${NC}"
    CACHE_ARG="--no-cache"
fi

# Build Linux testing image
echo ""
echo -e "${YELLOW}Building Linux D-Bus testing image...${NC}"
docker-compose -f docker/docker-compose.yml build $CACHE_ARG linux-test

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "Available images:"
docker images | grep znotify || true

echo ""
echo "Usage:"
echo "  ./scripts/test-linux.sh test   - Run tests"
echo "  ./scripts/test-linux.sh shell  - Interactive shell"
echo "  ./scripts/test-linux.sh bench  - Run benchmarks"
