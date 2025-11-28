#!/bin/bash
# Test the installer in Docker

set -e

echo "🧪 Testing AirSync Installer in Docker..."
echo ""

# Build fresh container
echo "Building test container..."
docker-compose build --no-cache

# Run installer and verify in same container
echo ""
echo "Running installer..."
docker-compose run --rm pi-zero-2w bash -c "
    cd /app/installer/scripts &&
    chmod +x install.sh &&
    ./install.sh &&
    echo '' &&
    echo '🔍 Verifying installation...' &&
    echo '' &&
    echo 'Checking shairport-sync...' &&
    which shairport-sync &&
    shairport-sync -V &&
    echo '' &&
    echo 'Checking airsync-detect...' &&
    which airsync-detect &&
    airsync-detect &&
    echo '' &&
    echo 'Checking airsync-generate-config...' &&
    which airsync-generate-config &&
    echo '' &&
    echo 'Checking config files...' &&
    ls -la /etc/shairport-sync.conf &&
    ls -la /etc/airsync/ &&
    echo '' &&
    echo 'Verifying config file contents (prevents soxr crash)...' &&
    if grep -q 'interpolation = \"soxr\"' /etc/shairport-sync.conf && \
       grep -q 'alsa = {' /etc/shairport-sync.conf && \
       grep -q 'output_device' /etc/shairport-sync.conf; then
        echo '  ✓ Config has soxr interpolation'
        echo '  ✓ Config has ALSA section'
        echo '  ✓ Config has output device'
    else
        echo '  ✗ Config missing required settings!'
        exit 1
    fi &&
    echo '' &&
    echo '✅ All verification checks passed!'
"

echo ""
echo "✅ Installer test complete!"
