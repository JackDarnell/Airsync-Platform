# AirSync Installer

One-command installation for headless Raspberry Pi systems.

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/yourusername/airsync/main/installer/scripts/install.sh | sudo bash
```

Or download and inspect first:

```bash
curl -sSL https://raw.githubusercontent.com/yourusername/airsync/main/installer/scripts/install.sh > install.sh
less install.sh
sudo bash install.sh
```

## What It Does

The installer automatically:

1. ✅ **Detects your OS** (Debian, Ubuntu, Raspberry Pi OS, Arch)
2. ✅ **Installs system dependencies** (ALSA, Avahi, build tools)
3. ✅ **Installs Rust** (if not already present)
4. ✅ **Builds shairport-sync** from source (latest stable)
5. ✅ **Builds AirSync daemon** from source
6. ✅ **Detects hardware** and generates optimal config
7. ✅ **Sets up systemd service** (auto-start on boot)
8. ✅ **Starts the receiver** immediately

Takes ~5-10 minutes on Raspberry Pi Zero 2 W (first time).

## After Installation

Your AirPlay 2 receiver is running!

### Check Status

```bash
systemctl status shairport-sync
```

### View Hardware Detection

```bash
airsync-detect
```

### Customize Device Name

Edit the config:
```bash
sudo nano /etc/shairport-sync.conf
# Change: name = "AirSync";
# To:     name = "Living Room";
sudo systemctl restart shairport-sync
```

## Supported Systems

| OS | Architecture | Status |
|----|--------------|--------|
| Raspberry Pi OS | ARM64 | ✅ Tested |
| Debian 12+ | ARM64/x86_64 | ✅ Supported |
| Ubuntu 22.04+ | ARM64/x86_64 | ✅ Supported |
| Arch Linux | ARM64/x86_64 | ✅ Supported |

## Troubleshooting

### Installer fails with permission error

Make sure to run with `sudo`:
```bash
curl -sSL ... | sudo bash
```

### Can't find device in iOS Control Center

1. Check if service is running:
   ```bash
   systemctl status shairport-sync
   ```

2. Ensure Avahi is running:
   ```bash
   systemctl status avahi-daemon
   ```

3. Check network connectivity:
   ```bash
   ping 8.8.8.8
   ```

### Audio not working

1. List audio devices:
   ```bash
   aplay -l
   ```

2. Edit `/etc/shairport-sync.conf` and set correct `output_device`

3. Restart service:
   ```bash
   sudo systemctl restart shairport-sync
   ```

## Uninstall

```bash
sudo systemctl stop shairport-sync
sudo systemctl disable shairport-sync
sudo rm /usr/local/bin/shairport-sync
sudo rm /usr/local/bin/airsync-detect
sudo rm -rf /opt/airsync
sudo rm -rf /etc/airsync
sudo userdel airsync
```

## Manual Installation

If you prefer to install manually, see [Manual Installation Guide](../docs/manual-install.md).

## Development

Test the installer locally in Docker:

```bash
cd docker/pi-simulator
./test-installer.sh
```
