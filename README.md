# AirSync Platform

A TDD-driven AirPlay 2 receiver that runs on minimal hardware (Raspberry Pi Zero 2 W) while gracefully scaling to more powerful devices. The system detects hardware capabilities at runtime and provides precise audio latency calibration through an iOS companion app.

Built in **Rust** for maximum performance, minimal memory footprint, and memory safety.

## Current State

**Status**: Foundation phase - hardware detection complete

The project is in its initial setup phase. We are following strict TDD principles where every component is tested before implementation.

### What's Complete

- ✅ Phase 1 specification document
- ✅ Cargo workspace structure
- ✅ Shared protocol types (device, messages, calibration)
- ✅ Hardware detection module (test-first, 8/8 tests passing)
  - CPU core detection
  - RAM detection
  - Board identification (Pi Zero 2 W, Pi 4, Pi 5)
  - Audio output detection (I2S, USB, HDMI, Headphone)
  - Default system readers for production use
- ✅ Hardware profile selection (5/5 tests passing)
  - Minimal profile (256MB+): AirPlay only
  - Standard profile (1GB+): AirPlay + Web UI
  - Enhanced profile (4GB+): All features including local TTS
- ✅ Shairport-sync config generator (10/10 tests passing)
  - Dynamic config generation based on hardware profile
  - Audio output device mapping
  - Interpolation method selection (basic/soxr)
  - Buffer sizing for performance/quality tradeoff
  - Cover art enable/disable based on RAM
- ✅ CLI tool for hardware detection (`detect-hardware`)

### What's Next

- ⏳ Test installer on real Raspberry Pi hardware
- ⏳ Shairport-sync process manager (start/stop/monitor/recover)
- ⏳ Configuration generator with interactive prompts
- ⏳ WebSocket API for iOS companion app

## Installation

### Offline Installation (Recommended for Testing)

For local testing or offline installation:

```bash
# On your Mac/Linux machine:
./installer/scripts/package-for-pi.sh

# This creates: airsync-offline-installer.tar.gz

# Copy to your Raspberry Pi:
scp airsync-offline-installer.tar.gz pi@raspberrypi.local:~/

# On the Raspberry Pi:
tar -xzf airsync-offline-installer.tar.gz
cd airsync
sudo SOURCE_DIR=$PWD ./install.sh
```

This automatically:

- ✅ Detects your hardware (Pi 4 1GB+, Pi 5, etc.)
- ✅ Installs all dependencies (Rust, build tools, ALSA, Avahi)
- ✅ Builds and installs shairport-sync
- ✅ Builds and installs AirSync daemon from bundled source
- ✅ Generates optimized configuration
- ✅ Sets up systemd service (auto-start on boot)

Takes ~5-10 minutes. After installation, your device appears in iOS Control Center!

### One-Command Install (Future - requires GitHub)

```bash
# This will work once the repo is published:
curl -sSL https://raw.githubusercontent.com/JackDarnell/airsync/main/installer/scripts/install.sh | sudo bash
```

See [installer/README.md](installer/README.md) for troubleshooting and manual installation.

## Development Setup

### Prerequisites

- Rust 1.75+ (install via [rustup](https://rustup.rs/))
- Docker Desktop (for testing in Pi environment)
- Git
- (Optional) Cross-compilation tools for ARM

### Building from Source

```bash
# Clone repository
git clone https://github.com/JackDarnell/airsync.git
cd airsync

# Build all crates
cargo build

# Build optimized release binary
cargo build --release
```

### Quick Verification with Docker

The fastest way to verify your code works in a Linux environment:

```bash
# One command to test everything in a simulated Pi environment
./docker/test-in-docker.sh
```

Or manually:

```bash
# Enter Docker Pi simulator
cd docker/pi-simulator && docker-compose up -d
docker-compose exec pi-zero-2w bash

# Inside container:
cargo test
cargo run --bin detect-hardware

# Exit
exit
docker-compose down
```

This simulates a Raspberry Pi Zero 2 W with mocked `/proc` files.

### Testing the Installer

To test the full installation process in Docker:

```bash
cd docker/pi-simulator
./test-installer.sh
```

This runs the complete installer in a fresh Debian container.

## Running Tests

This project follows Google's TDD philosophy. All features are tested before implementation.

### Test Commands

```bash
# Run all tests
cargo test

# Run tests for a specific crate
cargo test -p airsync-receiver-core

# Run tests in watch mode (requires cargo-watch)
cargo install cargo-watch
cargo watch -x test

# Run tests with output
cargo test -- --nocapture

# Run tests with coverage (requires cargo-tarpaulin)
cargo install cargo-tarpaulin
cargo tarpaulin --out Html
```

### Test Organization

Tests follow the 80/15/5 pyramid:

- **Unit tests (80%)**: Embedded in source files with `#[cfg(test)]` modules
- **Integration tests (15%)**: In `tests/` directory (coming soon)
- **E2E tests (5%)**: Full system tests with Docker Pi emulator (coming soon)

### Current Test Results

```
✓ 23 tests passing across 2 crates

Hardware Detection (8 tests):
  ✓ CPU core counting
  ✓ RAM detection and parsing
  ✓ Board identification (Pi Zero 2 W, Pi 4, Pi 5)
  ✓ Audio output detection (I2S, USB, Headphone)
  ✓ Preferred output selection

Hardware Profile Selection (5 tests):
  ✓ Minimal profile selection (low RAM)
  ✓ Standard profile selection (1GB RAM)
  ✓ Enhanced profile selection (4GB RAM)
  ✓ Fallback to minimal for insufficient resources
  ✓ Highest fitting profile selection

Shairport-Sync Config Generation (10 tests):
  ✓ Interpolation method selection
  ✓ Buffer length optimization
  ✓ Cover art enable/disable
  ✓ Custom device naming
  ✓ Audio output device mapping (I2S, USB, HDMI)
  ✓ Config file rendering
```

## Project Structure

```
airsync/
├── crates/
│   ├── receiver-core/        # Main receiver daemon (Rust)
│   └── shared-protocol/      # Cross-platform types (Rust)
├── installer/                # One-command installation ✅
│   ├── scripts/install.sh    # Main installer script
│   └── README.md             # Installation guide
├── docker/                   # Docker Pi simulator ✅
│   └── pi-simulator/         # Test environment
├── docs/                     # Architecture documentation ✅
│   └── shairport-sync-integration.md
├── ios-app/                  # Swift iOS companion (coming soon)
├── tools/
│   ├── hw-profiler/          # Hardware benchmarking (coming soon)
│   └── latency-analyzer/     # Calibration data analysis (coming soon)
└── Cargo.toml                # Workspace configuration
```

### Crate Overview

- **airsync-shared-protocol**: Type definitions for hardware capabilities, WebSocket messages, and calibration protocol
- **airsync-receiver-core**: Main daemon with hardware detection, AirPlay integration, and calibration engine
  - Binary: `detect-hardware` - CLI tool to detect and display hardware capabilities
  - Module: `hardware` - Runtime hardware detection and capability assessment
  - Module: `airplay` - Shairport-sync configuration generation and process management

## Development Workflow

### TDD Approach

1. **Red**: Write a failing test that defines desired behavior
2. **Green**: Write minimal code to make the test pass
3. **Refactor**: Clean up code while keeping tests green
4. **Repeat**: Move to next smallest unit of work

### Code Philosophy

- **Self-describing code**: Use descriptive function names that represent the domain
- **Avoid comments**: Code should explain itself through clear naming
- **High cohesion**: Related functionality stays together
- **Low coupling**: Minimize dependencies between modules
- **Shared test data**: Use centralized test fixtures that are easy to modify

### Local Development

```bash
# Run tests in watch mode during development
cargo watch -x test

# Check code with clippy (Rust linter)
cargo clippy

# Format code
cargo fmt

# Build for development (fast compilation, debug symbols)
cargo build

# Build for release (optimized, small binary)
cargo build --release

# Run hardware detection tool (requires Raspberry Pi or Linux with /proc)
cargo run --bin detect-hardware
```

### Cross-Compilation for Raspberry Pi

```bash
# Add ARM target
rustup target add aarch64-unknown-linux-gnu

# Install cross-compilation toolchain (macOS example)
brew install aarch64-unknown-linux-gnu

# Build for Pi Zero 2 W / Pi 4 / Pi 5 (ARM64)
cargo build --release --target aarch64-unknown-linux-gnu

# Binary will be at: target/aarch64-unknown-linux-gnu/release/
```

## Architecture Highlights

### Why Rust?

- **Memory Safety**: No segfaults, no data races, guaranteed at compile time
- **Zero-Cost Abstractions**: Performance of C with high-level expressiveness
- **Tiny Binaries**: Release builds optimized for size (typically <2MB stripped)
- **Low Memory Footprint**: Perfect for Pi Zero 2 W's 512MB RAM
- **Excellent Testing**: Built-in test framework with mocking support
- **Cross-Compilation**: Easy to build ARM binaries from any platform

### Hardware Detection (✅ Complete)

Runtime detection of device capabilities drives feature availability:

- **CPU cores**: Parsed from `/proc/cpuinfo`
- **RAM**: Parsed from `/proc/meminfo`
- **Board ID**: Identifies Pi Zero 2 W, Pi 4, Pi 5 from model string
- **Audio outputs**: Detects I2S DAC, USB audio, HDMI, headphone jack via ALSA
- **Hardware profiles**: Selects minimal/standard/enhanced based on resources

**Implementation**: `crates/receiver-core/src/hardware/detector.rs`

### AirPlay 2 Receiver (Partial - Config Gen Complete)

Wraps shairport-sync with:

- ✅ **Dynamic configuration** based on hardware profile
  - Profile-aware interpolation (basic/soxr)
  - RAM-aware buffer sizing
  - Audio output device detection
- ⏳ Process management (start/stop/monitor)
- ⏳ Health monitoring and auto-recovery
- ⏳ mDNS advertisement with device metadata

**Architecture**: We don't bundle shairport-sync. It's installed as a system dependency, and we generate configs + manage the process. See [docs/shairport-sync-integration.md](docs/shairport-sync-integration.md)

### Latency Calibration (Coming Soon)

iOS app measures speaker-to-microphone delay:

- Chirp-based audio signal (2kHz-8kHz sweep)
- Cross-correlation algorithm for precise timing
- ±5ms accuracy target

## Contributing

See [PHASE_1_SPECIFICATION.md](./PHASE_1_SPECIFICATION.md) for detailed technical specifications.

### Development Principles

1. **Test first, always**: No code without tests
2. **Smallest valuable increment**: Break work into tiny, testable units
3. **Clean as you go**: Refactor immediately, don't accumulate debt
4. **Domain-driven naming**: Names should reflect business concepts

## CI/CD

Tests run automatically on every push:

- Unit and integration tests on Ubuntu latest
- E2E tests in QEMU ARM64 emulator
- 80%+ code coverage required on critical paths

## License

[License information to be added]

## Support

For issues and questions, please use GitHub Issues.
