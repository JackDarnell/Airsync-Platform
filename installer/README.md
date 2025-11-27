# AirSync Installer

One-command installation for headless Raspberry Pi systems, with support for both online and offline installation.

## Online Install (Recommended)

Install directly from GitHub (requires internet):

```bash
curl -sSL https://raw.githubusercontent.com/JackDarnell/Airsync-Platform/main/installer/scripts/install.sh | sudo bash
```

Or download and inspect first:

```bash
curl -sSL https://raw.githubusercontent.com/JackDarnell/Airsync-Platform/main/installer/scripts/install.sh > install.sh
less install.sh
sudo bash install.sh
```

## Offline Install

For systems without internet access:

```bash
# On your computer with internet:
./installer/scripts/package-for-pi.sh

# Copy to Pi:
scp airsync-offline-installer.tar.gz pi@raspberrypi.local:~/

# On the Pi:
tar -xzf airsync-offline-installer.tar.gz
cd airsync
sudo SOURCE_DIR=$PWD ./install.sh
```

## What It Does

The installer automatically:

1. ✅ **Detects your OS** (Debian, Ubuntu, Raspberry Pi OS, Arch)
2. ✅ **Installs system dependencies** (ALSA, Avahi, build tools, AirPlay 2 libraries)
3. ✅ **Installs Rust** (if not already present)
4. ✅ **Installs NQPTP** (timing companion for AirPlay 2)
5. ✅ **Builds shairport-sync with AirPlay 2 support** from source (latest stable)
6. ✅ **Builds AirSync daemon** from source
7. ✅ **Detects hardware** and generates optimal config
8. ✅ **Prompts you to select audio output device** (HDMI, headphone jack, USB, I2S DAC, etc.)
9. ✅ **Sets up systemd services** (auto-start on boot)
10. ✅ **Starts the receiver** immediately

Takes ~5-10 minutes on Raspberry Pi Zero 2 W (first time).

### Interactive Setup

During installation, you'll be prompted to select your audio output device:
```
Available audio output devices:
================================
  1) hw:0,0
     Headphones - bcm2835 Headphones
  2) hw:1,0
     vc4-hdmi - MAI PCM i2s-hifi-0

Select audio output device [1-2] (default: 1):
```

Simply enter the number corresponding to your preferred output device.

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

| OS              | Architecture | Status       |
| --------------- | ------------ | ------------ |
| Raspberry Pi OS | ARM64        | ✅ Tested    |
| Debian 12+      | ARM64/x86_64 | ✅ Supported |
| Ubuntu 22.04+   | ARM64/x86_64 | ✅ Supported |
| Arch Linux      | ARM64/x86_64 | ✅ Supported |

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
