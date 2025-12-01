# AirSync Platform

A TDD-driven AirPlay 2 receiver that runs on minimal hardware (Raspberry Pi Zero 2 W) while gracefully scaling to more powerful devices. The system detects hardware capabilities at runtime and provides precise audio latency calibration through an iOS companion app.

Built in **Rust** for maximum performance, minimal memory footprint, and memory safety.

## Current State

**Status**: Receiver service, Bonjour discovery, and structured calibration implemented; installer provisions systemd + Avahi and pre-generates calibration signals.

### What's Complete

- ✅ Phase 1 specification document
- ✅ Cargo workspace structure
- ✅ Shared protocol types (device, messages, calibration)
- ✅ Hardware detection module (test-first)
  - CPU core/RAM detection, board identification (Pi Zero 2 W, Pi 4, Pi 5)
  - Audio output detection (I2S, USB, HDMI, Headphone)
- ✅ Shairport-sync config generator
  - Dynamic config generation with audio output mapping, soxr interpolation, buffer sizing, cover art
- ✅ Receiver HTTP service (Axum)
  - Discovery: Avahi TXT for `_airsync._tcp` with name/ver/api/caps/id
  - Calibration (structured mode): `/api/calibration/spec`, `/api/calibration/request`, `/api/calibration/ready`, `/api/calibration/result`
    - Pre-generated 48 kHz structured WAV with marker metadata
    - Warm-up hum + multi-frequency markers for reliable detection
    - Applies latency via shairport config + restart
  - Settings endpoints: `/api/settings` (GET/POST) update shairport config and restart shairport-sync
  - Receiver info endpoint and TXT helpers
- ✅ CLI tools: `airsync-detect`, `airsync-generate-config`, `airsync-receiver-service` binary
- ✅ Installer provisions
  - Builds/installs receiver service and pre-generated calibration WAV
  - Installs systemd unit for receiver service and shairport-sync
  - Publishes Avahi `_airsync._tcp` with caps/name/id
  - Creates state dir `/var/lib/airsync` for receiver_id/cache

### What's Next

- ⏳ Test installer on real Raspberry Pi hardware
- ⏳ Shairport-sync process manager (start/stop/monitor/recover)
- ⏳ Configuration generator with interactive prompts
- ⏳ WebSocket API for iOS companion app

## Installation

### One-Command Install (Online)

The fastest way to install on a Raspberry Pi with internet:

```bash
curl -sSL https://raw.githubusercontent.com/JackDarnell/Airsync-Platform/main/installer/scripts/install.sh | sudo bash
```

This automatically:
- ✅ Downloads source from GitHub
- ✅ Detects your hardware (Pi 4 1GB+, Pi 5, etc.)
- ✅ Installs all dependencies (Rust, build tools, ALSA, Avahi)
- ✅ Builds and installs shairport-sync
- ✅ Builds and installs AirSync daemon
- ✅ Generates optimized configuration
- ✅ Sets up systemd service (auto-start on boot)

Takes ~5-10 minutes. After installation, your device appears in iOS Control Center!

### Offline Installation (No Internet Required)

For offline installation or local testing:

```bash
# On your Mac/Linux machine:
./installer/scripts/package-for-pi.sh

# Copy to your Raspberry Pi:
scp airsync-offline-installer.tar.gz pi@raspberrypi.local:~/

# On the Raspberry Pi:
tar -xzf airsync-offline-installer.tar.gz
cd airsync
sudo SOURCE_DIR=$PWD ./install.sh
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

# Run iOS calibration unit tests (requires Xcode + simulator)
cd mobile-applications/AirSync
xcodebuild test -scheme AirSync -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Test Organization

Tests follow the 80/15/5 pyramid:

- **Unit tests (80%)**: Embedded in source files with `#[cfg(test)]` modules
- **Integration tests (15%)**: In `tests/` directory (coming soon)
- **E2E tests (5%)**: Full system tests with Docker Pi emulator (coming soon)

### Current Test Results (local)

```
✓ Receiver Core (38 tests) — hardware detection, shairport config, calibration applier, structured calibration spec + playback, Avahi/TXT helpers, settings API
✓ Shared Protocol — serialization for calibration markers/spec
✓ iOS unit build — calibration models/detector/spec decoding (sim build; deprecation warnings only)
```

## Project Structure

```
airsync/
├── crates/
│   ├── receiver-core/        # Main receiver daemon (Rust)
│   └── shared-protocol/      # Cross-platform types (Rust)
├── installer/                # One-command installation ✅ (installs receiver + shairport + Avahi)
│   ├── scripts/install.sh    # Main installer script
│   └── README.md             # Installation guide
├── docker/                   # Docker Pi simulator ✅
│   └── pi-simulator/         # Test environment
├── docs/                     # Architecture documentation ✅
│   └── shairport-sync-integration.md
├── mobile-applications/AirSync/  # Swift iOS companion app (calibration + pairing)
├── tools/
│   ├── hw-profiler/          # Hardware benchmarking (coming soon)
│   └── latency-analyzer/     # Calibration data analysis (coming soon)
└── Cargo.toml                # Workspace configuration
```

### Crate Overview

- **airsync-shared-protocol**: Type definitions for hardware capabilities, WebSocket messages, and calibration protocol
- **airsync-receiver-core**: Receiver HTTP service, hardware detection, shairport config, calibration engine, pairing/settings API
  - Binaries: `detect-hardware`, `generate-config`, `airsync-receiver-service`
  - Modules: `hardware` (detection), `airplay` (config), `http` (pairing/calibration/settings)

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

### Latency Calibration (Implemented)

Structured calibration flow between receiver and iOS:

- Receiver generates a structured 48 kHz WAV at install/startup with warm-up hum, multi-frequency markers, and trailing click.
- `GET /api/calibration/spec` returns marker metadata (sample rate, length, markers) for iOS.
- `POST /api/calibration/request` + `POST /api/calibration/ready` schedule playback using server time; playback uses the pre-generated WAV (or chirp fallback).
- iOS records with padded window, runs matched filtering over the markers (sub-sample interpolation), computes latency/confidence, and can apply the offset via `POST /api/calibration/result`.

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
