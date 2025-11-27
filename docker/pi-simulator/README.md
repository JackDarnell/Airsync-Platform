# Pi Simulator for Testing

Quick Docker environment to test hardware detection without a real Raspberry Pi.

## Quick Start

```bash
# Build and start the simulator
docker-compose up -d

# Enter the container
docker-compose exec pi-zero-2w bash

# Inside container: build and test
cargo test
cargo build --release
cargo run --bin detect-hardware

# Exit container
exit

# Stop the simulator
docker-compose down
```

## What This Simulates

- **Raspberry Pi Zero 2 W** environment
- 4 CPU cores (ARMv8)
- 512MB RAM
- Debian Bookworm base
- Mock `/proc/cpuinfo` and `/proc/meminfo`

## Limitations

This is NOT a full emulator:
- No actual ARM CPU (uses your host architecture)
- No real audio hardware
- No GPIO/I2S hardware
- ALSA commands will fail (no sound card)

For full hardware testing, use a real Raspberry Pi or QEMU with full ARM emulation.

## One-Liner Quick Test

```bash
cd docker/pi-simulator && docker-compose run --rm pi-zero-2w bash -c "cargo test && cargo run --bin detect-hardware"
```
