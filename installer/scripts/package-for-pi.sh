#!/bin/bash
# Package AirSync for offline installation on Raspberry Pi
# This creates a tarball with source code and installer script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT}"

echo "Packaging AirSync for offline installation..."
echo ""

# Create temporary directory for packaging
TEMP_DIR=$(mktemp -d)
PACKAGE_DIR="$TEMP_DIR/airsync"
mkdir -p "$PACKAGE_DIR"

# Copy source code (excluding build artifacts and git)
echo "Copying source code..."
rsync -a \
    --exclude 'target' \
    --exclude '.git' \
    --exclude 'node_modules' \
    --exclude '.DS_Store' \
    "$PROJECT_ROOT/crates" \
    "$PROJECT_ROOT/Cargo.toml" \
    "$PROJECT_ROOT/Cargo.lock" \
    "$PROJECT_ROOT/README.md" \
    "$PACKAGE_DIR/"

# Copy installer script
echo "Copying installer..."
cp "$SCRIPT_DIR/install.sh" "$PACKAGE_DIR/"
chmod +x "$PACKAGE_DIR/install.sh"

# Create installation instructions
cat > "$PACKAGE_DIR/INSTALL.txt" <<'EOF'
AirSync Offline Installation
============================

This package contains everything needed to install AirSync on a Raspberry Pi
without internet access.

Prerequisites:
- Raspberry Pi 4 (1GB+ RAM) or Pi 5
- Raspberry Pi OS (Debian Bookworm) with desktop or lite
- Root access (sudo)

Installation Steps:
-------------------

1. Copy this entire 'airsync' directory to your Raspberry Pi:

   # On your computer (adjust IP address):
   scp -r airsync pi@raspberrypi.local:~/

2. SSH into your Raspberry Pi:

   ssh pi@raspberrypi.local

3. Run the installer:

   cd ~/airsync
   sudo SOURCE_DIR=$PWD ./install.sh

The installer will:
- Install system dependencies (requires internet for apt packages)
- Build shairport-sync from source
- Build AirSync from the bundled source code
- Configure and start the service

After installation, your Pi will appear as "AirSync" in iOS Control Center!

Troubleshooting:
----------------

If you see "No AirSync source code found":
- Make sure you're running: sudo SOURCE_DIR=$PWD ./install.sh
- The SOURCE_DIR must point to the directory containing Cargo.toml

If shairport-sync build fails:
- Ensure you have internet for apt-get to install dependencies
- Check that all build dependencies were installed

For more help, see README.md
EOF

# Create tarball
OUTPUT_FILE="$OUTPUT_DIR/airsync-offline-installer.tar.gz"
echo "Creating tarball..."
tar -czf "$OUTPUT_FILE" -C "$TEMP_DIR" airsync

# Cleanup
rm -rf "$TEMP_DIR"

# Show results
TARBALL_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
echo ""
echo "✅ Package created successfully!"
echo ""
echo "   File: $OUTPUT_FILE"
echo "   Size: $TARBALL_SIZE"
echo ""
echo "To install on Raspberry Pi:"
echo "  1. Copy to Pi: scp $OUTPUT_FILE pi@raspberrypi.local:~/"
echo "  2. SSH to Pi:  ssh pi@raspberrypi.local"
echo "  3. Extract:    tar -xzf airsync-offline-installer.tar.gz"
echo "  4. Install:    cd airsync && sudo SOURCE_DIR=\$PWD ./install.sh"
echo ""
