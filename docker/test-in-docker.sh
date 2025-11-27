#!/bin/bash
# Quick script to test hardware detection in Docker

set -e

echo "🐳 Starting Pi Simulator..."
cd docker/pi-simulator

# Build if not already built
if ! docker images | grep -q airsync-pi-simulator; then
    echo "Building Docker image (first time only)..."
    docker-compose build
fi

echo ""
echo "🧪 Running tests in Pi environment..."
docker-compose run --rm pi-zero-2w bash -c "
    echo '=== Building project ===' &&
    cargo build --release 2>&1 | grep -E '(Compiling|Finished)' &&
    echo '' &&
    echo '=== Running tests ===' &&
    cargo test --quiet &&
    echo '' &&
    echo '=== Hardware Detection Output ===' &&
    cargo run --bin detect-hardware --release 2>/dev/null
"

echo ""
echo "✅ Docker test complete!"
