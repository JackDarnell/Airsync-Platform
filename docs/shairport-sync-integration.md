# Shairport-Sync Integration Architecture

## Overview

AirSync uses a **wrapper approach** for shairport-sync integration. We don't bundle or fork shairport-sync; instead, we:

1. **Manage it as a system dependency** (installed separately)
2. **Generate configuration dynamically** based on hardware profile
3. **Orchestrate the process** (start/stop/monitor/recover)
4. **Provide a clean API** for our daemon to use

This follows the Unix philosophy: let shairport-sync handle the AirPlay protocol (what it does best), while we handle orchestration and hardware adaptation.

## Architecture

```
┌─────────────────────────────────────────────┐
│         AirSync Receiver Daemon             │
│                                             │
│  ┌─────────────┐        ┌───────────────┐  │
│  │  Hardware   │───────▶│    Config     │  │
│  │  Detection  │        │  Generator    │  │
│  └─────────────┘        └───────┬───────┘  │
│                                 │           │
│                         Generates config    │
│                                 │           │
│  ┌──────────────────────────────▼────────┐  │
│  │      Process Manager                  │  │
│  │  - Start/Stop shairport-sync          │  │
│  │  - Health monitoring                  │  │
│  │  - Auto-recovery                      │  │
│  └──────────────┬────────────────────────┘  │
└─────────────────┼───────────────────────────┘
                  │
                  │ Spawns & monitors
                  ▼
         ┌──────────────────┐
         │  shairport-sync  │
         │  (External C     │
         │   process)       │
         └──────────────────┘
```

## Component Breakdown

### 1. Config Generator (`airplay/config.rs`) ✅ **Implemented**

**Purpose**: Generate shairport-sync configuration based on hardware capabilities

**Test coverage**: 10 tests passing
- Interpolation method selection (basic for minimal, soxr for standard+)
- Buffer sizing (larger for constrained hardware)
- Cover art enable/disable based on RAM
- Audio output device mapping
- Custom device naming

**Example usage**:
```rust
let config = generate_config_from_profile(
    &hardware_profile,
    Some("Living Room"),
    AudioOutput::I2S,
);

let config_file = render_config_file(&config);
// Writes to /etc/shairport-sync.conf
```

### 2. Process Manager (`airplay/process.rs`) 🚧 **Next iteration**

**Purpose**: Manage shairport-sync lifecycle

**Planned features**:
- Start process with generated config
- Monitor process health (check if running)
- Auto-restart on crash
- Graceful shutdown
- Log capture and forwarding

**API design**:
```rust
pub struct ShairportProcess {
    config: ShairportConfig,
    handle: Option<Child>,
}

impl ShairportProcess {
    pub fn start(&mut self) -> Result<()>;
    pub fn stop(&mut self) -> Result<()>;
    pub fn restart(&mut self) -> Result<()>;
    pub fn is_healthy(&self) -> bool;
}
```

### 3. Health Monitor (Future)

Periodic checks:
- Process still running?
- Responding to network requests?
- Audio output functioning?

Auto-recovery actions:
- Restart on crash
- Reload config on change
- Alert on repeated failures

## Installation & Dependencies

### Shairport-Sync Installation

**Option 1: System Package** (Easiest)
```bash
# Debian/Ubuntu/Raspberry Pi OS
sudo apt-get update
sudo apt-get install shairport-sync
```

**Option 2: Build from Source** (Latest features)
```bash
# Install dependencies
sudo apt-get install build-essential git autoconf automake \
    libtool libpopt-dev libconfig-dev libasound2-dev avahi-daemon \
    libavahi-client-dev libssl-dev libsoxr-dev

# Clone and build
git clone https://github.com/mikebrady/shairport-sync.git
cd shairport-sync
autoreconf -fi
./configure --sysconfdir=/etc --with-alsa --with-soxr --with-avahi \
    --with-ssl=openssl --with-systemd --with-metadata
make
sudo make install
```

**Option 3: Our Installer Script** (Coming soon)
```bash
curl -sSL install.airsync.dev | bash
# Will detect system and install shairport-sync + AirSync daemon
```

### Runtime Requirements

- **shairport-sync** installed and in PATH
- **ALSA** for audio output
- **Avahi** for mDNS/Bonjour
- **libconfig** for config parsing
- **libsoxr** for high-quality resampling (optional but recommended)

## Configuration Strategy

### Profile-Based Generation

Different hardware profiles get different configs:

| Profile | Interpolation | Buffer | Cover Art | Rationale |
|---------|---------------|--------|-----------|-----------|
| Minimal | Basic | 0.15s | No | CPU/RAM constrained |
| Standard | Soxr | 0.1s | Yes | Balanced quality/performance |
| Enhanced | Soxr | 0.1s | Yes | Maximum quality |

### Audio Output Mapping

| Detected Output | ALSA Device | Notes |
|----------------|-------------|-------|
| I2S DAC | `hw:0,0` | High quality, direct |
| USB Audio | `hw:1,0` | External DAC |
| HDMI | `hdmi` | TV/Monitor |
| Headphone | `hw:0,0` | Built-in 3.5mm |

### Dynamic Config Updates

When hardware profile changes:
1. Detect new capabilities
2. Generate new config
3. Write to `/etc/shairport-sync.conf`
4. Restart shairport-sync process
5. Verify health

## Future Enhancements

### Process Manager (Next)
- Implement process lifecycle management
- Add health monitoring
- Implement auto-recovery

### Advanced Features (Later)
- Multi-room sync coordination
- Metadata extraction and forwarding
- Statistics collection (connection count, uptime)
- Remote control API

### iOS App Integration
- Send metadata to iOS app
- Allow remote configuration changes
- Display connection status

## Testing Strategy

### Unit Tests (Current)
✅ Config generation for all profiles
✅ Audio output device mapping
✅ Buffer and interpolation selection
✅ Cover art enable/disable logic

### Integration Tests (Next)
- Process start/stop/restart
- Config file writing
- Health monitoring
- Auto-recovery

### E2E Tests (Future)
- Full installation in Docker
- Actual AirPlay connection from iOS
- Audio playback verification
- Multi-device scenarios

## Security Considerations

1. **Config file permissions**: Write to `/etc` requires root
2. **Process isolation**: Run shairport-sync as dedicated user
3. **Network exposure**: Only expose mDNS and AirPlay ports
4. **Config validation**: Sanitize user-provided device names

## References

- [Shairport-Sync GitHub](https://github.com/mikebrady/shairport-sync)
- [Shairport-Sync Documentation](https://github.com/mikebrady/shairport-sync/blob/master/README.md)
- [AirPlay Protocol](https://en.wikipedia.org/wiki/AirPlay)
