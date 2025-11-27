#!/bin/bash
# AirSync One-Command Installer
# curl -sSL https://raw.githubusercontent.com/JackDarnell/airsync/main/installer/scripts/install.sh | bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SHAIRPORT_VERSION="4.3.2"
INSTALL_DIR="/opt/airsync"
SERVICE_USER="airsync"
CONFIG_DIR="/etc/airsync"

# Bundled source mode - installer can work offline if source is provided
# Set SOURCE_ARCHIVE environment variable to point to airsync source tarball
# or SOURCE_DIR to point to extracted source directory
SOURCE_ARCHIVE="${SOURCE_ARCHIVE:-}"
SOURCE_DIR="${SOURCE_DIR:-}"

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     AirSync Installer                  ║${NC}"
echo -e "${GREEN}║     One-command AirPlay 2 receiver     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (use sudo)${NC}"
    exit 1
fi

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        echo -e "${RED}Error: Cannot detect OS${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Detected OS: $OS $OS_VERSION"
}

# Install system dependencies
install_dependencies() {
    echo ""
    echo "Installing system dependencies..."

    case "$OS" in
        debian|ubuntu|raspbian)
            apt-get update
            apt-get install -y \
                build-essential \
                git \
                autoconf \
                automake \
                libtool \
                libpopt-dev \
                libconfig-dev \
                libasound2-dev \
                avahi-daemon \
                libavahi-client-dev \
                libssl-dev \
                libsoxr-dev \
                libsystemd-dev \
                curl
            ;;
        arch)
            pacman -Syu --noconfirm \
                base-devel \
                git \
                autoconf \
                automake \
                libtool \
                popt \
                libconfig \
                alsa-lib \
                avahi \
                openssl \
                libsoxr \
                systemd
            ;;
        *)
            echo -e "${RED}Error: Unsupported OS: $OS${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}✓${NC} Dependencies installed"
}

# Install Rust if not present
install_rust() {
    if command -v cargo &> /dev/null; then
        echo -e "${GREEN}✓${NC} Rust already installed: $(cargo --version)"
        return
    fi

    echo ""
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    echo -e "${GREEN}✓${NC} Rust installed: $(cargo --version)"
}

# Build and install shairport-sync
install_shairport_sync() {
    if command -v shairport-sync &> /dev/null; then
        echo -e "${GREEN}✓${NC} shairport-sync already installed: $(shairport-sync -V)"
        return
    fi

    echo ""
    echo "Building shairport-sync from source..."

    cd /tmp
    rm -rf shairport-sync
    git clone --depth 1 --branch "$SHAIRPORT_VERSION" https://github.com/mikebrady/shairport-sync.git
    cd shairport-sync

    autoreconf -fi

    # Detect if systemd is available
    local SYSTEMD_FLAG=""
    if [ -d "/run/systemd/system" ]; then
        # Explicitly set systemd unit directory to avoid install errors
        SYSTEMD_FLAG="--with-systemd --with-systemdsystemunitdir=/lib/systemd/system"
        echo "Systemd detected, enabling systemd integration"
    else
        echo "No systemd detected, building without systemd support"
    fi

    ./configure \
        --sysconfdir=/etc \
        --with-alsa \
        --with-soxr \
        --with-avahi \
        --with-ssl=openssl \
        $SYSTEMD_FLAG \
        --with-metadata

    make -j$(nproc)
    make install || {
        # If make install fails (common in containers), try installing just the binary
        echo -e "${YELLOW}Warning: Full install failed, installing binary only${NC}"
        install -m 0755 shairport-sync /usr/local/bin/
        install -d /etc
        install -m 0644 ./scripts/shairport-sync.conf /etc/shairport-sync.conf.sample
        [ -f /etc/shairport-sync.conf ] || cp ./scripts/shairport-sync.conf /etc/shairport-sync.conf
    }

    cd /tmp
    rm -rf shairport-sync

    echo -e "${GREEN}✓${NC} shairport-sync installed"
}

# Create service user
create_user() {
    if id "$SERVICE_USER" &>/dev/null; then
        echo -e "${GREEN}✓${NC} User $SERVICE_USER already exists"
        return
    fi

    echo ""
    echo "Creating service user..."
    useradd -r -s /bin/false -d /nonexistent "$SERVICE_USER"
    usermod -a -G audio "$SERVICE_USER"
    echo -e "${GREEN}✓${NC} User $SERVICE_USER created"
}

# Build and install AirSync daemon
install_airsync() {
    echo ""
    echo "Building AirSync daemon..."

    # Determine source location (priority order):
    # 1. Development mode (/app/Cargo.toml exists)
    # 2. Bundled source directory (SOURCE_DIR set)
    # 3. Bundled source archive (SOURCE_ARCHIVE set)
    # 4. Error - no source available

    if [ -f "/app/Cargo.toml" ]; then
        echo "Development mode: using local source at /app"
        cd /app
    elif [ -n "$SOURCE_DIR" ] && [ -d "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/Cargo.toml" ]; then
        echo "Using bundled source directory: $SOURCE_DIR"
        cd "$SOURCE_DIR"
    elif [ -n "$SOURCE_ARCHIVE" ] && [ -f "$SOURCE_ARCHIVE" ]; then
        echo "Extracting bundled source archive: $SOURCE_ARCHIVE"
        mkdir -p "$INSTALL_DIR"
        tar -xzf "$SOURCE_ARCHIVE" -C "$INSTALL_DIR" --strip-components=1
        cd "$INSTALL_DIR"
    elif [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/Cargo.toml" ]; then
        echo "Using existing installation at $INSTALL_DIR"
        cd "$INSTALL_DIR"
    else
        echo -e "${RED}Error: No AirSync source code found${NC}"
        echo ""
        echo "Please provide source code using one of these methods:"
        echo "  1. Set SOURCE_DIR=/path/to/airsync"
        echo "  2. Set SOURCE_ARCHIVE=/path/to/airsync.tar.gz"
        echo "  3. Extract source to $INSTALL_DIR before running installer"
        echo ""
        echo "For offline installation, download the release tarball from GitHub"
        exit 1
    fi

    # Verify Cargo.toml exists
    if [ ! -f "Cargo.toml" ]; then
        echo -e "${RED}Error: Cargo.toml not found in source directory${NC}"
        exit 1
    fi

    # Build release binary
    cargo build --release --bin detect-hardware

    # Install binary
    cp target/release/detect-hardware /usr/local/bin/airsync-detect
    chmod +x /usr/local/bin/airsync-detect

    # Create config directory
    mkdir -p "$CONFIG_DIR"
    chown "$SERVICE_USER:$SERVICE_USER" "$CONFIG_DIR"

    echo -e "${GREEN}✓${NC} AirSync daemon installed"
}

# Detect hardware and generate initial config
setup_configuration() {
    echo ""
    echo "Detecting hardware and generating configuration..."

    # Run hardware detection
    /usr/local/bin/airsync-detect > "$CONFIG_DIR/hardware.json" || true

    # Generate shairport-sync config
    # This will be done by our daemon, but for now create basic config
    cat > /etc/shairport-sync.conf <<EOF
general = {
    name = "AirSync";
    interpolation = "basic";
    output_backend = "alsa";
};

alsa = {
    output_device = "hw:0,0";
    audio_backend_buffer_desired_length_in_seconds = 0.15;
};

metadata = {
    enabled = "yes";
    include_cover_art = "no";
    pipe_name = "/tmp/shairport-sync-metadata";
};

sessioncontrol = {
    session_timeout = 20;
};
EOF

    chown "$SERVICE_USER:$SERVICE_USER" /etc/shairport-sync.conf
    echo -e "${GREEN}✓${NC} Configuration generated"
}

# Set up systemd service
setup_systemd() {
    # Skip if systemd not available (e.g., in Docker)
    if [ ! -d "/run/systemd/system" ]; then
        echo -e "${YELLOW}⊘${NC} Systemd not available, skipping service setup"
        echo "   To start manually: shairport-sync -c /etc/shairport-sync.conf"
        return
    fi

    echo ""
    echo "Setting up systemd service..."

    # Enable shairport-sync service
    systemctl enable shairport-sync 2>/dev/null || true
    systemctl start shairport-sync 2>/dev/null || true

    echo -e "${GREEN}✓${NC} Services configured"
}

# Cleanup build artifacts to save disk space
cleanup_build_artifacts() {
    echo ""
    echo "Cleaning up build artifacts..."

    # Clean up Cargo build cache (saves ~500MB on Pi Zero)
    if [ -d "$HOME/.cargo/registry" ]; then
        du -sh "$HOME/.cargo/registry" 2>/dev/null || true
        rm -rf "$HOME/.cargo/registry/cache"
        rm -rf "$HOME/.cargo/registry/src"
    fi

    # Clean up any remaining temp files
    rm -rf /tmp/shairport-sync 2>/dev/null || true

    echo -e "${GREEN}✓${NC} Build artifacts cleaned up"
}

# Verify installation completed successfully
verify_installation() {
    echo ""
    echo "Verifying installation..."

    local ERRORS=0

    # Check shairport-sync
    if ! command -v shairport-sync &> /dev/null; then
        echo -e "${RED}✗${NC} shairport-sync not found in PATH"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}✓${NC} shairport-sync installed: $(shairport-sync -V 2>&1 | head -n1)"
    fi

    # Check airsync-detect
    if ! command -v airsync-detect &> /dev/null; then
        echo -e "${RED}✗${NC} airsync-detect not found in PATH"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}✓${NC} airsync-detect installed"
    fi

    # Check config files
    if [ ! -f /etc/shairport-sync.conf ]; then
        echo -e "${RED}✗${NC} Configuration file missing"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}✓${NC} Configuration file present"
    fi

    # Check user
    if ! id "$SERVICE_USER" &>/dev/null; then
        echo -e "${RED}✗${NC} Service user not created"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}✓${NC} Service user created"
    fi

    if [ $ERRORS -gt 0 ]; then
        echo ""
        echo -e "${RED}Installation completed with $ERRORS error(s)${NC}"
        return 1
    fi

    echo -e "${GREEN}✓${NC} All verification checks passed"
}

# Main installation flow
main() {
    detect_os
    install_dependencies
    install_rust
    install_shairport_sync
    create_user
    install_airsync
    setup_configuration
    setup_systemd
    cleanup_build_artifacts
    verify_installation

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Installation Complete! 🎉          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Your AirPlay 2 receiver is now running!"
    echo ""
    echo "Device name: AirSync"
    echo "Status: systemctl status shairport-sync"
    echo ""
    echo "To customize your installation:"
    echo "  - Edit /etc/shairport-sync.conf"
    echo "  - Run: systemctl restart shairport-sync"
    echo ""
    echo "View hardware detection:"
    echo "  airsync-detect"
    echo ""
}

# Run main function
main
