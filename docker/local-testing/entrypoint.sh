#!/bin/bash
set -e

echo "🚀 AirSync Local Testing Environment"
echo "====================================="
echo ""

# Install NQPTP
if ! command -v nqptp &> /dev/null; then
    echo "Building NQPTP..."
    cd /tmp
    git clone https://github.com/mikebrady/nqptp.git
    cd nqptp
    autoreconf -fi
    ./configure --with-systemd-startup
    make
    make install
    cd /
    rm -rf /tmp/nqptp
    echo "✓ NQPTP installed"
fi

# Install shairport-sync
if ! command -v shairport-sync &> /dev/null; then
    echo "Building shairport-sync..."
    cd /tmp
    git clone --depth 1 --branch development https://github.com/mikebrady/shairport-sync.git
    cd shairport-sync
    autoreconf -fi
    ./configure \
        --sysconfdir=/etc \
        --with-alsa \
        --with-soxr \
        --with-avahi \
        --with-ssl=openssl \
        --with-systemd \
        --with-systemdsystemunitdir=/lib/systemd/system \
        --with-airplay-2 \
        --with-metadata
    make -j$(nproc)
    make install
    cd /
    rm -rf /tmp/shairport-sync
    echo "✓ shairport-sync installed"
fi

# Regenerate config with specified device name
DEVICE_NAME="${DEVICE_NAME:-AirSync Local Test}"
AUDIO_DEVICE="${AUDIO_DEVICE:-hw:0,0}"

echo ""
echo "Generating configuration..."
echo "  Device name: $DEVICE_NAME"
echo "  Audio device: $AUDIO_DEVICE"

airsync-generate-config /etc/shairport-sync.conf "$DEVICE_NAME" --device "$AUDIO_DEVICE"

echo ""
echo "Starting services..."

# Start DBus (required for Avahi)
mkdir -p /var/run/dbus
rm -f /var/run/dbus/pid
dbus-daemon --system --fork

# Start Avahi daemon (for mDNS/Bonjour discovery)
avahi-daemon -D

# Start NQPTP (required for AirPlay 2)
nqptp -d || nqptp &

# Wait a moment for services to initialize
sleep 2

echo ""
echo "✅ Services started!"
echo ""
echo "📱 AirPlay receiver is now discoverable as: $DEVICE_NAME"
echo ""
echo "How to test from macOS:"
echo "  1. Open Music, Spotify, or any audio app"
echo "  2. Click the AirPlay icon (🔊 or speaker icon)"
echo "  3. Select '$DEVICE_NAME' from the list"
echo "  4. Play audio!"
echo ""
echo "Checking for AirPlay service..."
sleep 1

# Check if service is advertising (timeout after 5 seconds)
timeout 5 avahi-browse -ptr _airplay._tcp 2>/dev/null | head -5 || echo "Service check timed out (this is okay)"

echo ""
echo "Starting shairport-sync in foreground..."
echo "Press Ctrl+C to stop"
echo ""

# Run shairport-sync in foreground with verbose output
exec shairport-sync -v
