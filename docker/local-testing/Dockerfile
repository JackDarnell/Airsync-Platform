# AirSync Local Testing Environment
# Simulates DietPi/Debian device for AirPlay testing from macOS
FROM debian:bookworm-slim

# Install system dependencies (matching installer)
RUN apt-get update && apt-get install -y \
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
    libplist-utils \
    libsodium-dev \
    libavutil-dev \
    libavcodec-dev \
    libavformat-dev \
    uuid-dev \
    libgcrypt-dev \
    xxd \
    curl \
    vim \
    dbus \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Set working directory
WORKDIR /app

# Copy entire project
COPY . .

# Build Rust binaries
RUN cargo build --release --bin detect-hardware && \
    cargo build --release --bin generate-config

# Install binaries
RUN install -m 0755 target/release/detect-hardware /usr/local/bin/airsync-detect && \
    install -m 0755 target/release/generate-config /usr/local/bin/airsync-generate-config

# Create config directory
RUN mkdir -p /etc/airsync

# Generate default config (will be overridden by entrypoint if needed)
RUN airsync-generate-config /etc/shairport-sync.conf "AirSync Local Test" || true

# Copy entrypoint script
COPY docker/local-testing/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
