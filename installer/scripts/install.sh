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
                libplist-dev \
                libsodium-dev \
                libavutil-dev \
                libavcodec-dev \
                libavformat-dev \
                uuid-dev \
                libgcrypt-dev \
                xxd \
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
                systemd \
                libplist \
                libsodium \
                ffmpeg \
                libsndfile
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

# Install NQPTP (required for AirPlay 2)
install_nqptp() {
    if command -v nqptp &> /dev/null; then
        echo -e "${GREEN}✓${NC} NQPTP already installed"
        return
    fi

    echo ""
    echo "Installing NQPTP (required for AirPlay 2)..."

    cd /tmp
    rm -rf nqptp
    git clone https://github.com/mikebrady/nqptp.git
    cd nqptp

    autoreconf -fi
    ./configure --with-systemd-startup
    make
    make install || {
        # Fallback: install binary manually
        echo -e "${YELLOW}Warning: Full install failed, installing manually${NC}"
        install -m 0755 nqptp /usr/local/bin/
    }

    cd /tmp
    rm -rf nqptp

    # Enable and start NQPTP service if systemd is available
    if [ -d "/run/systemd/system" ]; then
        systemctl enable nqptp 2>/dev/null || true
        systemctl start nqptp 2>/dev/null || true
    fi

    echo -e "${GREEN}✓${NC} NQPTP installed"
}

# Helper function to install shairport-sync systemd service
install_shairport_service() {
    if [ ! -d "/run/systemd/system" ]; then
        return  # Systemd not available
    fi

    if [ -f /lib/systemd/system/shairport-sync.service ]; then
        return  # Service already installed
    fi

    echo ""
    echo "Checking systemd service installation..."

    # Try to find service file in multiple locations
    local SERVICE_FILE=""
    local SEARCH_PATHS=(
        "/tmp/shairport-sync/scripts/shairport-sync.service"
        "./scripts/shairport-sync.service"
        "/usr/local/share/shairport-sync/scripts/shairport-sync.service"
    )

    for path in "${SEARCH_PATHS[@]}"; do
        if [ -f "$path" ]; then
            SERVICE_FILE="$path"
            echo "Found service file at: $SERVICE_FILE"
            break
        fi
    done

    # If not found, download it
    if [ -z "$SERVICE_FILE" ]; then
        echo "Service file not found locally, downloading from GitHub..."
        local CURRENT_DIR=$(pwd)
        cd /tmp
        rm -rf shairport-sync-service

        if git clone --depth 1 --branch "$SHAIRPORT_VERSION" https://github.com/mikebrady/shairport-sync.git shairport-sync-service 2>/dev/null; then
            SERVICE_FILE="/tmp/shairport-sync-service/scripts/shairport-sync.service"
        else
            echo -e "${YELLOW}Warning: Could not download shairport-sync service file${NC}"
            cd "$CURRENT_DIR"
            return 1
        fi

        cd "$CURRENT_DIR"
    fi

    # Install the service file
    if [ -f "$SERVICE_FILE" ]; then
        install -d /lib/systemd/system
        install -m 0644 "$SERVICE_FILE" /lib/systemd/system/shairport-sync.service
        systemctl daemon-reload 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Systemd service file installed"
    else
        echo -e "${YELLOW}Warning: Could not install shairport-sync.service${NC}"
        return 1
    fi

    # Cleanup temporary download
    rm -rf /tmp/shairport-sync-service 2>/dev/null || true
}

# Build and install shairport-sync
install_shairport_sync() {
    if command -v shairport-sync &> /dev/null; then
        echo -e "${GREEN}✓${NC} shairport-sync already installed: $(shairport-sync -V)"
        # Even if binary exists, ensure systemd service is installed
        install_shairport_service
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
        --with-airplay-2 \
        --with-metadata

    make -j$(nproc)
    make install || {
        # If make install fails (common in containers), try installing manually
        echo -e "${YELLOW}Warning: Full install failed, installing manually${NC}"

        # Install binary
        install -m 0755 shairport-sync /usr/local/bin/

        # Install config files
        install -d /etc
        install -m 0644 ./scripts/shairport-sync.conf /etc/shairport-sync.conf.sample
        [ -f /etc/shairport-sync.conf ] || cp ./scripts/shairport-sync.conf /etc/shairport-sync.conf

        # Install systemd service if systemd is available
        if [ -d "/run/systemd/system" ]; then
            echo "Installing systemd service file..."
            install -d /lib/systemd/system
            install -m 0644 ./scripts/shairport-sync.service /lib/systemd/system/shairport-sync.service
            systemctl daemon-reload 2>/dev/null || true
        fi
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
    # 4. Existing installation at /opt/airsync
    # 5. Download from GitHub (requires internet)

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
        # No local source found - download from GitHub
        echo "No local source found, downloading from GitHub..."

        if [ -d "$INSTALL_DIR" ]; then
            echo "Updating existing installation..."
            cd "$INSTALL_DIR"
            git pull
        else
            echo "Cloning AirSync repository..."
            git clone https://github.com/JackDarnell/Airsync-Platform.git "$INSTALL_DIR"
            cd "$INSTALL_DIR"
        fi

        echo -e "${GREEN}✓${NC} Source downloaded from GitHub"
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

# Select audio output device
select_audio_device() {
    echo ""
    echo "Detecting available audio devices..."

    if [ -n "${AUDIO_DEVICE_OVERRIDE:-}" ]; then
        SELECTED_AUDIO_DEVICE="$AUDIO_DEVICE_OVERRIDE"
        echo -e "${GREEN}✓${NC} Using audio device from AUDIO_DEVICE_OVERRIDE: $SELECTED_AUDIO_DEVICE"
        return
    fi

    # Check if aplay is available
    if ! command -v aplay &> /dev/null; then
        echo -e "${YELLOW}Warning: aplay not found, using default device${NC}"
        SELECTED_AUDIO_DEVICE="hw:0,0"
        return
    fi

    # Get list of hardware devices from aplay -l (more reliable than -L)
    local devices=()
    local descriptions=()

    # Parse aplay -l to get card/device numbers
    while IFS= read -r line; do
        if [[ "$line" =~ ^card\ ([0-9]+):.*device\ ([0-9]+): ]]; then
            local card="${BASH_REMATCH[1]}"
            local device="${BASH_REMATCH[2]}"
            local hw_device="hw:${card},${device}"

            # Get the device name/description
            local desc=$(echo "$line" | sed 's/^card [0-9]*: \([^,]*\), device [0-9]*: \(.*\) \[.*/\1 - \2/')

            devices+=("$hw_device")
            descriptions+=("$desc")
        fi
    done < <(aplay -l 2>/dev/null)

    # If no devices found, use default
    if [ ${#devices[@]} -eq 0 ]; then
        echo -e "${YELLOW}No audio devices detected, using default: hw:0,0${NC}"
        SELECTED_AUDIO_DEVICE="hw:0,0"
        return
    fi

    # Display menu
    echo ""
    echo "Available audio output devices:"
    echo "================================"
    local i=1
    for idx in "${!devices[@]}"; do
        echo "  $i) ${devices[$idx]}"
        echo "     ${descriptions[$idx]}"
        ((i++))
    done
    echo ""

    # Auto-select if only one device
    if [ ${#devices[@]} -eq 1 ]; then
        SELECTED_AUDIO_DEVICE="${devices[0]}"
        echo -e "${GREEN}✓${NC} Selected: $SELECTED_AUDIO_DEVICE (${descriptions[0]})"
        return
    fi

    # Prompt for selection
    while true; do
        local choice=""
        if [ -t 0 ]; then
            read -r -p "Select audio output device [1-${#devices[@]}] (default: 1): " choice
        else
            # When piped (curl | bash), read from TTY if available
            if [ -e /dev/tty ]; then
                read -r -p "Select audio output device [1-${#devices[@]}] (default: 1): " choice < /dev/tty
            else
                choice=""
            fi
        fi

        # Default to first device if no input
        if [[ -z "$choice" ]]; then
            choice=1
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#devices[@]} ]; then
            SELECTED_AUDIO_DEVICE="${devices[$((choice-1))]}"
            echo -e "${GREEN}✓${NC} Selected: $SELECTED_AUDIO_DEVICE (${descriptions[$((choice-1))]})"
            break
        else
            echo -e "${RED}Invalid selection. Please enter a number between 1 and ${#devices[@]}${NC}"
        fi
    done
}

# Detect hardware and generate initial config
setup_configuration() {
    echo ""
    echo "Detecting hardware and generating configuration..."

    # Run hardware detection
    /usr/local/bin/airsync-detect > "$CONFIG_DIR/hardware.json" || true

    # Select audio output device
    select_audio_device

    # Generate shairport-sync config
    # This will be done by our daemon, but for now create basic config
    cat > /etc/shairport-sync.conf <<EOF
general = {
    name = "AirSync";
    interpolation = "basic";
    output_backend = "alsa";
};

alsa = {
    output_device = "$SELECTED_AUDIO_DEVICE";
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

    # Check NQPTP
    if ! command -v nqptp &> /dev/null; then
        echo -e "${RED}✗${NC} NQPTP not found in PATH"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}✓${NC} NQPTP installed"
    fi

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

    # Check systemd service file (if systemd is available)
    if [ -d "/run/systemd/system" ]; then
        if [ ! -f /lib/systemd/system/shairport-sync.service ]; then
            echo -e "${RED}✗${NC} Systemd service file not found"
            ERRORS=$((ERRORS + 1))
        else
            echo -e "${GREEN}✓${NC} Systemd service file installed"
        fi
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
    install_nqptp
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
