#!/bin/bash
# Test znotify in Linux Docker container

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}ZNotify Linux Testing${NC}"
echo "======================================"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Parse command line arguments
COMMAND="${1:-test}"

case "$COMMAND" in
    test)
        echo -e "${YELLOW}Running tests in Linux container...${NC}"
        docker compose -f docker/docker-compose.yml run --rm test
        ;;
    bench)
        echo -e "${YELLOW}Running benchmarks in Linux container...${NC}"
        docker compose -f docker/docker-compose.yml run --rm bench
        ;;
    shell)
        echo -e "${YELLOW}Starting interactive shell in Linux container...${NC}"
        docker compose -f docker/docker-compose.yml run --rm linux-test
        ;;
    build)
        echo -e "${YELLOW}Building in Linux container...${NC}"
        docker compose -f docker/docker-compose.yml run --rm linux-test zig build --cache-dir /tmp/zig-cache
        ;;
    clean)
        echo -e "${YELLOW}Cleaning up Docker resources...${NC}"
        docker compose -f docker/docker-compose.yml down -v
        docker rmi znotify-linux-test:latest 2>/dev/null || true
        echo -e "${GREEN}Cleanup complete${NC}"
        ;;
    *)
        echo "Usage: $0 {test|bench|shell|build|clean}"
        echo ""
        echo "Commands:"
        echo "  test   - Run tests in Linux container (default)"
        echo "  bench  - Run benchmarks in Linux container"
        echo "  shell  - Start interactive shell in Linux container"
        echo "  build  - Build project in Linux container"
        echo "  clean  - Remove Docker images and volumes"
        exit 1
        ;;
esac

echo -e "${GREEN}Done!${NC}"
