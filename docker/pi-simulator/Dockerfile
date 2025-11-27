# Simulate a Raspberry Pi environment for testing
FROM debian:bookworm-slim

# Install Rust and dependencies
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    alsa-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Set working directory
WORKDIR /app

# Copy mock /proc files
COPY mock-proc/cpuinfo /tmp/cpuinfo
COPY mock-proc/meminfo /tmp/meminfo

# Default command
CMD ["/bin/bash"]
