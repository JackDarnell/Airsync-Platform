# AirSync Local Testing Environment

Quick local testing of AirPlay pairing from macOS to a Docker container simulating a DietPi/Debian device.

## What This Does

Runs a complete AirSync AirPlay 2 receiver in Docker that:
- ✅ Builds NQPTP and shairport-sync from source (development branch)
- ✅ Uses host network for mDNS/Bonjour discovery
- ✅ Appears as "AirSync Local Test" in macOS AirPlay menu
- ✅ Tests pairing and connection handshake
- ✅ Validates configuration generation
- ⚠️ Audio output depends on host audio device availability

## Quick Start

### Prerequisites

- macOS (for AirPlay sender)
- Docker Desktop installed and running
- ~5 minutes for initial build

### Run It

```bash
cd docker/local-testing
bash test-local.sh
```

**That's it!** The script will:
1. Build the Docker container (~3-5 minutes first time)
2. Start the AirSync receiver
3. Wait for services to initialize
4. Show you how to test

### Test AirPlay Pairing

Once the receiver is running:

1. **Open any audio app** - Music, Spotify, Safari, etc.
2. **Click AirPlay icon** (🔊) in menu bar or app
3. **Select "AirSync Local Test"** from the device list
4. **Play audio** and verify the connection works

You should see:
- Device appears in AirPlay menu
- Connection establishes successfully
- Container logs show pairing activity

## Manual Usage

### Start Receiver

```bash
docker-compose up -d
```

### View Logs

```bash
# Live logs
docker-compose logs -f

# Last 50 lines
docker-compose logs --tail=50
```

### Stop Receiver

```bash
docker-compose down
```

### Browse for AirPlay Devices

```bash
# macOS built-in tool
dns-sd -B _airplay._tcp local.
```

### Enter Container

```bash
docker-compose exec airsync-receiver bash

# Inside container:
shairport-sync -V              # Check version
cat /etc/shairport-sync.conf   # View config
avahi-browse -a                # Browse mDNS services
```

## Customization

### Change Device Name

Edit `docker-compose.yml`:
```yaml
environment:
  - DEVICE_NAME=My Custom Name
  - AUDIO_DEVICE=hw:0,0
```

Then restart:
```bash
docker-compose up -d --force-recreate
```

### Enable Audio Output (Optional)

If your macOS has `/dev/snd` (rare), uncomment in `docker-compose.yml`:
```yaml
privileged: true
devices:
  - /dev/snd:/dev/snd
```

## What Gets Tested

| Feature | Tested | Notes |
|---------|--------|-------|
| **mDNS Discovery** | ✅ Yes | Via host network mode |
| **AirPlay Pairing** | ✅ Yes | Full handshake |
| **Connection** | ✅ Yes | Establishes stream |
| **Config Generation** | ✅ Yes | Uses Rust generator |
| **NQPTP** | ✅ Yes | AirPlay 2 timing |
| **Shairport-sync** | ✅ Yes | Development branch |
| **Audio Output** | ⚠️ Limited | Docker audio constraints |
| **Multi-room** | ⚠️ Limited | Requires multiple containers |

## Troubleshooting

### Device Doesn't Appear in AirPlay Menu

**Check services are running:**
```bash
docker-compose logs | grep -i "started\|error"
```

**Browse for mDNS services:**
```bash
dns-sd -B _airplay._tcp local.
# Should show "AirSync Local Test"
```

**Restart container:**
```bash
docker-compose restart
```

### Connection Fails or Drops

**Check logs for errors:**
```bash
docker-compose logs -f
# Look for AirPlay negotiation errors
```

**Verify network mode:**
```bash
docker inspect airsync-local-test | grep NetworkMode
# Should show "host"
```

### Build Fails

**Clean and rebuild:**
```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

**Check Rust installation:**
```bash
docker-compose run --rm airsync-receiver cargo --version
```

## Architecture

```
┌─────────────────────────────────────────┐
│           macOS Host                    │
│                                         │
│  ┌──────────────┐    ┌──────────────┐  │
│  │   macOS      │───▶│   Docker     │  │
│  │  Music App   │    │   AirSync    │  │
│  │   (Sender)   │    │  (Receiver)  │  │
│  └──────────────┘    └──────────────┘  │
│         │                    │          │
│         └────────────────────┘          │
│           Host network                  │
│       (network_mode: host)              │
│                                         │
│  mDNS/Bonjour broadcasts on localhost   │
└─────────────────────────────────────────┘
```

## Files

```
docker/local-testing/
├── README.md              # This file
├── Dockerfile             # Container build instructions
├── docker-compose.yml     # Container orchestration
├── entrypoint.sh         # Startup script
└── test-local.sh         # Quick test script
```

## Iteration Time

- **First run:** ~5 minutes (includes build)
- **Subsequent runs:** ~10 seconds (cached build)
- **Code changes:** ~2 minutes (rebuild only changed layers)

## Comparison to Other Testing Methods

| Method | Setup Time | Iteration | Realism | Best For |
|--------|-----------|-----------|---------|----------|
| **Unit Tests** | None | 10s | Low | Code validation |
| **This (macOS Local)** | 5min | 10s | High | AirPlay pairing |
| **iPhone → Docker** | 15min | 5min | Highest | iOS-specific |
| **Real Hardware** | 30min+ | 30min+ | Production | Final validation |

## Next Steps

After local testing succeeds:
1. Run on real iPhone (see `docker/real-device-testing/`)
2. Deploy to real Raspberry Pi / Orange Pi / DietPi
3. Test audio quality with real speakers

## Related Documentation

- [Pi Simulator Testing](../pi-simulator/README.md) - Headless testing
- [Installer Tests](../../installer/tests/) - Integration tests
- [Main README](../../README.md) - Project overview
