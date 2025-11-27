# AirSync Platform — Phase 1 Specification

A TDD-driven AirPlay 2 receiver with runtime hardware detection and iOS latency calibration.

---

## Overview

Phase 1 delivers a production-ready AirPlay 2 receiver that runs on affordable hardware (Raspberry Pi 4 1GB and up). The system detects hardware capabilities at runtime and provides precise audio latency calibration through an iOS companion app. All supported systems receive the same high-quality configuration with Soxr interpolation and full AirPlay 2 features.

### Core Principles

- **TDD-first**: Every component is tested before implementation
- **Hardware-agnostic**: Runtime detection drives feature availability
- **Local development**: Docker-based Pi emulation for rapid iteration
- **E2E validation**: Full installation and runtime testing in CI

---

## Monorepo Structure

```
airsync/
├── packages/
│   ├── receiver-core/           # Main receiver daemon
│   │   ├── src/
│   │   │   ├── hardware/        # Hardware detection & capabilities
│   │   │   ├── airplay/         # Shairport-sync wrapper
│   │   │   ├── api/             # WebSocket + REST control
│   │   │   └── calibration/     # Audio latency engine
│   │   ├── tests/
│   │   │   ├── unit/
│   │   │   ├── integration/
│   │   │   └── e2e/
│   │   └── package.json
│   │
│   ├── ios-app/                 # Swift iOS companion
│   │   ├── AirSync/
│   │   │   ├── Discovery/       # Bonjour/mDNS
│   │   │   ├── Pairing/         # Device pairing flow
│   │   │   ├── Calibration/     # Microphone latency detection
│   │   │   └── Settings/        # Device configuration
│   │   ├── AirSyncTests/
│   │   └── AirSyncUITests/
│   │
│   ├── shared-protocol/         # Cross-platform definitions
│   │   ├── src/
│   │   │   ├── messages.ts      # WebSocket message schemas
│   │   │   ├── device.ts        # Device capability types
│   │   │   └── calibration.ts   # Calibration protocol
│   │   └── tests/
│   │
│   └── installer/               # One-command device setup
│       ├── scripts/
│       │   ├── install.sh       # Main installer
│       │   ├── detect-hw.sh     # Hardware detection
│       │   └── configure.sh     # Post-install config
│       └── tests/
│
├── firmware/
│   ├── docker/                  # Development containers
│   │   ├── pi-emulator/         # Raspberry Pi emulation
│   │   │   ├── Dockerfile
│   │   │   ├── qemu-setup.sh
│   │   │   └── docker-compose.yml
│   │   └── test-runner/         # E2E test orchestration
│   │
│   ├── releases/                # Release build configs
│   │   ├── build.sh
│   │   └── changelog/
│   │
│   └── provisioning/            # First-boot setup
│       ├── firstboot.sh
│       └── network-config/
│
├── tools/
│   ├── hw-profiler/             # Hardware benchmarking
│   └── latency-analyzer/        # Calibration data analysis
│
├── .github/
│   └── workflows/
│       ├── test.yml             # Unit + integration tests
│       └── e2e.yml              # Full E2E in Pi emulator
│
├── docs/
│   ├── architecture.md
│   ├── hardware-support.md
│   ├── calibration-protocol.md
│   └── contributing.md
│
├── turbo.json                   # Turborepo config
├── pnpm-workspace.yaml
└── package.json
```

---

## Phase 1 Milestones

### 1A: Foundation & Local Development Environment

**Goal**: Establish TDD infrastructure and Pi emulation for local development.

**Deliverables**:

1. **Monorepo scaffolding**

   - Turborepo + pnpm workspaces
   - Shared TypeScript config
   - ESLint + Prettier configuration
   - Vitest for unit/integration tests

2. **Docker Pi emulator**

   - QEMU-based ARM64 emulation (Debian Bookworm)
   - Simulated hardware interfaces (I2S, GPIO, USB audio)
   - Network simulation for mDNS testing
   - Volume mounts for rapid code iteration

3. **E2E test harness**
   - Installation script testing
   - Service lifecycle validation
   - Network discovery verification

**Test Requirements** (write tests first):

```typescript
// packages/receiver-core/tests/e2e/installation.test.ts
describe("Installation E2E", () => {
  it("installs successfully on fresh Debian system", async () => {
    const container = await startPiEmulator();
    const result = await container.exec("curl -sSL install.airsync.dev | bash");
    expect(result.exitCode).toBe(0);
    expect(await container.serviceStatus("airsync")).toBe("running");
  });

  it("installer is idempotent", async () => {
    // Running twice should not break anything
  });

  it("handles missing dependencies gracefully", async () => {
    // Should install all deps or fail with clear message
  });
});
```

---

### 1B: Hardware Detection System

**Goal**: Detect device capabilities at runtime to enable/disable features.

**Capabilities to Detect**:

| Capability    | Detection Method                  | Feature Impact                 |
| ------------- | --------------------------------- | ------------------------------ |
| CPU cores     | `/proc/cpuinfo`                   | Concurrent processing limits   |
| RAM           | `/proc/meminfo`                   | Buffer sizes, caching strategy |
| Audio outputs | ALSA enumeration                  | Available output options       |
| I2S DAC       | Device tree / `/proc/device-tree` | High-quality audio path        |
| USB audio     | `lsusb` + ALSA                    | External DAC support           |
| Network       | Interface enumeration             | WiFi vs Ethernet priority      |
| GPU/VideoCore | `/dev/vchiq` presence             | Future: HW-accelerated DSP     |

**Minimum Requirements**:

```typescript
// packages/receiver-core/src/hardware/requirements.ts
interface MinimumRequirements {
  minCores: 4;
  minRamMB: 1024; // AirPlay 2 requires at least 1GB for reliable performance
  requiredAudio: ["alsa"];
}

function isCapable(capabilities: HardwareCapabilities): boolean {
  return (
    capabilities.cpuCores >= 4 &&
    capabilities.ramMB >= 1024 &&
    capabilities.audioOutputs.length > 0
  );
}
```

All capable systems run with the same high-quality configuration:

- **Soxr interpolation** for best audio quality
- **Cover art enabled**
- **0.1s audio buffer**
- **Full AirPlay 2 support** including multi-room sync

**Supported Hardware**:

- Raspberry Pi 4 Model B (1GB, 2GB, 4GB, 8GB)
- Raspberry Pi 5 (4GB, 8GB)
- Raspberry Pi 400 (4GB)
- Generic ARM64/x86_64 Linux systems with 1GB+ RAM

**Test Requirements**:

```typescript
// packages/receiver-core/tests/unit/hardware/detector.test.ts
describe("HardwareDetector", () => {
  it("correctly identifies Pi 4 as capable", async () => {
    const detector = new HardwareDetector(mockPi4System);
    const caps = await detector.detect();

    expect(caps.cpuCores).toBe(4);
    expect(caps.ramMB).toBeGreaterThanOrEqual(1024);
    expect(caps.boardId).toBe("raspberry-pi-4-model-b");
    expect(isCapable(caps)).toBe(true);
  });

  it("detects I2S DAC when present", async () => {
    const detector = new HardwareDetector(mockSystemWithI2SDAC);
    const caps = await detector.detect();

    expect(caps.audioOutputs).toContain("i2s");
    expect(caps.preferredOutput).toBe("i2s");
  });

  it("falls back to USB audio when no I2S", async () => {
    const detector = new HardwareDetector(mockSystemWithUSBAudio);
    const caps = await detector.detect();

    expect(caps.audioOutputs).toContain("usb");
    expect(caps.preferredOutput).toBe("usb");
  });

  it("rejects Pi Zero 2 W (insufficient RAM)", async () => {
    const detector = new HardwareDetector(mockPiZero2WSystem); // 4 cores but only 512MB
    const caps = await detector.detect();

    expect(caps.cpuCores).toBe(4);
    expect(caps.ramMB).toBe(512);
    expect(isCapable(caps)).toBe(false);
  });

  it("rejects Pi Zero W (insufficient cores and RAM)", async () => {
    const detector = new HardwareDetector(mockPiZeroWSystem); // 1 core, 512MB
    const caps = await detector.detect();

    expect(caps.cpuCores).toBe(1);
    expect(caps.ramMB).toBe(512);
    expect(isCapable(caps)).toBe(false);
  });
});
```

---

### 1C: AirPlay 2 Receiver Core

**Goal**: Wrap shairport-sync with configuration management and health monitoring.

**Components**:

1. **Shairport-sync manager**

   - Dynamic configuration generation based on hardware profile
   - Process lifecycle management (start/stop/restart)
   - Health monitoring and auto-recovery
   - Log aggregation

2. **Audio output router**

   - Detect and prioritize audio outputs
   - Handle output switching
   - Volume control abstraction

3. **mDNS advertisement**
   - Custom service metadata (device name, capabilities)
   - iOS app discovery support

**Configuration Generation**:

```typescript
// packages/receiver-core/src/airplay/config-generator.ts
function generateShairportConfig(
  capabilities: HardwareCapabilities,
  userConfig: UserConfig
): string {
  const config = {
    general: {
      name: userConfig.deviceName ?? `AirSync-${getShortId()}`,
      interpolation: "soxr", // Always use high-quality resampling
      output_backend: "alsa",
    },
    alsa: {
      output_device: capabilities.preferredOutput,
      audio_backend_buffer_desired_length_in_seconds: 0.1,
    },
    metadata: {
      enabled: "yes",
      include_cover_art: "yes",
      pipe_name: "/tmp/shairport-sync-metadata",
    },
    sessioncontrol: {
      session_timeout: 20,
    },
  };

  return toToml(config);
}
```

**Test Requirements**:

```typescript
// packages/receiver-core/tests/integration/airplay/receiver.test.ts
describe("AirPlay Receiver", () => {
  it("starts shairport-sync with high-quality configuration", async () => {
    const caps = await detectHardware();
    const receiver = new AirPlayReceiver(caps);
    await receiver.start();

    const config = await fs.readFile("/etc/shairport-sync.conf", "utf-8");
    expect(config).toContain('interpolation = "soxr"');
    expect(config).toContain('include_cover_art = "yes"');
  });

  it("advertises via mDNS with correct metadata", async () => {
    const caps = await detectHardware();
    const receiver = new AirPlayReceiver(caps);
    await receiver.start();

    const services = await discoverMdns("_raop._tcp");
    expect(services).toContainEqual(
      expect.objectContaining({ name: expect.stringContaining("AirSync") })
    );
  });

  it("recovers from shairport-sync crash", async () => {
    const caps = await detectHardware();
    const receiver = new AirPlayReceiver(caps);
    await receiver.start();

    await killProcess("shairport-sync");
    await sleep(2000);

    expect(await receiver.isHealthy()).toBe(true);
  });
});
```

---

### 1D: iOS Companion App — Discovery & Pairing

**Goal**: iOS app for device discovery, pairing, and basic control.

**Features**:

1. **Device Discovery**

   - Bonjour/mDNS scanning for `_airsync._tcp`
   - Display device name, board ID, version
   - Connection status monitoring

2. **Pairing Flow**

   - Generate pairing code on device
   - Secure WebSocket connection establishment
   - Certificate pinning for security

3. **Basic Control**
   - Device rename
   - Audio output selection
   - Volume control

**Architecture** (SwiftUI):

```swift
// AirSync/Discovery/DeviceScanner.swift
@MainActor
class DeviceScanner: ObservableObject {
    @Published var devices: [DiscoveredDevice] = []
    @Published var isScanning = false

    private let browser = NWBrowser(
        for: .bonjour(type: "_airsync._tcp", domain: nil),
        using: .tcp
    )

    func startScanning() {
        isScanning = true
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleResults(results)
        }
        browser.start(queue: .main)
    }
}
```

**Test Requirements** (XCTest):

```swift
// AirSyncTests/Discovery/DeviceScannerTests.swift
class DeviceScannerTests: XCTestCase {
    func testDiscoveryFindsLocalDevices() async throws {
        let scanner = DeviceScanner()
        scanner.startScanning()

        try await Task.sleep(for: .seconds(3))

        XCTAssertFalse(scanner.devices.isEmpty)
        XCTAssertTrue(scanner.devices.allSatisfy { $0.name.hasPrefix("AirSync") })
    }

    func testPairingEstablishesSecureConnection() async throws {
        let device = try await discoverFirstDevice()
        let connection = try await device.pair(code: "123456")

        XCTAssertTrue(connection.isSecure)
        XCTAssertNotNil(connection.certificate)
    }
}
```

---

### 1E: Latency Calibration System

**Goal**: Measure and compensate for speaker-to-microphone audio delay, similar to Apple TV and Belkin Soundform Connect.

**Calibration Protocol**:

```
┌─────────────┐                           ┌─────────────┐
│   iPhone    │                           │  Receiver   │
│  (iOS App)  │                           │  (AirSync)  │
└──────┬──────┘                           └──────┬──────┘
       │                                         │
       │  1. Request calibration                 │
       │────────────────────────────────────────▶│
       │                                         │
       │  2. Prepare ACK + countdown             │
       │◀────────────────────────────────────────│
       │                                         │
       │        ┌──────────────────────┐         │
       │        │ 3. User positions    │         │
       │        │    iPhone near       │         │
       │        │    speaker           │         │
       │        └──────────────────────┘         │
       │                                         │
       │  4. Start recording (mic)               │
       │  ◀─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─        │
       │                                         │
       │  5. Play test chirp sequence            │
       │         ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ▶│
       │                                         │  🔊 Chirp!
       │                                  ┌──────┴──────┐
       │                                  │ Speaker     │
       │         🎤 Record chirp          │ plays chirp │
       │◀ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─└──────┬──────┘
       │                                         │
       │  6. Send timing data                    │
       │────────────────────────────────────────▶│
       │                                         │
       │  7. Calculate & apply offset            │
       │◀────────────────────────────────────────│
       │                                         │
       │  8. Confirmation + verify playback      │
       │◀───────────────────────────────────────▶│
       │                                         │
```

**Chirp Design**:

```typescript
// packages/receiver-core/src/calibration/chirp-generator.ts
interface ChirpConfig {
  startFreq: 2000; // Hz - above most ambient noise
  endFreq: 8000; // Hz - sweep range
  duration: 50; // ms - short for precision
  repetitions: 5; // Multiple chirps for averaging
  intervalMs: 500; // Gap between chirps
}

function generateChirp(config: ChirpConfig): Float32Array {
  const sampleRate = 48000;
  const samples = Math.floor((sampleRate * config.duration) / 1000);
  const buffer = new Float32Array(samples);

  for (let i = 0; i < samples; i++) {
    const t = i / sampleRate;
    const freq =
      config.startFreq +
      (config.endFreq - config.startFreq) * (t / (config.duration / 1000));
    buffer[i] = Math.sin(2 * Math.PI * freq * t);
  }

  // Apply Hann window to reduce spectral leakage
  applyWindow(buffer, "hann");

  return buffer;
}
```

**Cross-Correlation Algorithm** (iOS side):

```swift
// AirSync/Calibration/LatencyDetector.swift
class LatencyDetector {
    func detectLatency(
        referenceChirp: [Float],
        recordedAudio: [Float],
        sampleRate: Int
    ) -> TimeInterval {
        // Normalize signals
        let normalizedRef = normalize(referenceChirp)
        let normalizedRec = normalize(recordedAudio)

        // Cross-correlate using Accelerate framework
        var correlation = [Float](repeating: 0, count: recordedAudio.count)
        vDSP_conv(normalizedRec, 1,
                  normalizedRef.reversed(), 1,
                  &correlation, 1,
                  vDSP_Length(recordedAudio.count),
                  vDSP_Length(referenceChirp.count))

        // Find peak
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(correlation, 1, &maxVal, &maxIdx, vDSP_Length(correlation.count))

        // Convert sample offset to time
        let offsetSamples = Int(maxIdx) - referenceChirp.count
        return TimeInterval(offsetSamples) / TimeInterval(sampleRate)
    }
}
```

**Test Requirements**:

```typescript
// packages/receiver-core/tests/unit/calibration/chirp.test.ts
describe("ChirpGenerator", () => {
  it("generates frequency sweep with correct parameters", () => {
    const chirp = generateChirp({
      startFreq: 2000,
      endFreq: 8000,
      duration: 50,
    });
    const spectrum = analyzeSpectrum(chirp);

    expect(spectrum.peakFrequencies).toContain(2000);
    expect(spectrum.peakFrequencies).toContain(8000);
  });

  it("applies window function to reduce artifacts", () => {
    const chirp = generateChirp(defaultConfig);

    // First and last samples should be near zero (windowed)
    expect(Math.abs(chirp[0])).toBeLessThan(0.01);
    expect(Math.abs(chirp[chirp.length - 1])).toBeLessThan(0.01);
  });
});

// packages/receiver-core/tests/integration/calibration/e2e.test.ts
describe("Calibration E2E", () => {
  it("measures simulated 50ms latency accurately", async () => {
    const receiver = await createTestReceiver();
    const iosSimulator = await createIOSSimulator();

    // Inject 50ms of delay in audio path
    receiver.setAudioDelay(50);

    const result = await iosSimulator.runCalibration(receiver);

    expect(result.measuredLatencyMs).toBeCloseTo(50, 5); // ±5ms tolerance
  });

  it("handles noisy environments gracefully", async () => {
    const receiver = await createTestReceiver();
    const iosSimulator = await createIOSSimulator({
      ambientNoise: "moderate_room",
    });

    const result = await iosSimulator.runCalibration(receiver);

    expect(result.confidence).toBeGreaterThan(0.8);
  });
});
```

---

## Development Environment

### Local Development with Docker

**Pi Emulator Setup**:

```dockerfile
# firmware/docker/pi-emulator/Dockerfile
FROM debian:bookworm-slim

# Install QEMU for ARM emulation
RUN apt-get update && apt-get install -y \
    qemu-user-static \
    binfmt-support \
    && rm -rf /var/lib/apt/lists/*

# Set up ARM64 environment
ENV QEMU_CPU=cortex-a53

# Simulate Pi hardware
COPY mock-hardware/ /sys/
COPY mock-proc/ /proc/

# Install audio stack
RUN apt-get update && apt-get install -y \
    alsa-utils \
    pulseaudio \
    avahi-daemon \
    && rm -rf /var/lib/apt/lists/*

# Volume for code mounting
VOLUME /app

WORKDIR /app
CMD ["/bin/bash"]
```

**Docker Compose for Full Stack**:

```yaml
# firmware/docker/docker-compose.yml
version: "3.8"

services:
  pi-emulator:
    build: ./pi-emulator
    privileged: true
    volumes:
      - ../../packages:/app/packages
      - ./mock-hardware:/sys/class
    ports:
      - "5000:5000" # API
      - "5353:5353" # mDNS
    networks:
      - airsync

  test-runner:
    build: ./test-runner
    depends_on:
      - pi-emulator
    volumes:
      - ../../:/workspace
    environment:
      - PI_HOST=pi-emulator
    networks:
      - airsync

networks:
  airsync:
    driver: bridge
```

**Development Workflow**:

```bash
# Start emulated environment
cd firmware/docker
docker-compose up -d

# Run tests against emulator
pnpm test:e2e

# Watch mode for rapid development
pnpm dev --filter=receiver-core
```

---

## CI/CD Pipeline

### GitHub Actions Workflows

**Test Workflow** (`.github/workflows/test.yml`):

```yaml
name: Test Suite

on:
  push:
    branches: [main]
  pull_request:

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v2
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "pnpm"

      - run: pnpm install
      - run: pnpm test:unit
      - run: pnpm test:integration

  e2e-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
        with:
          platforms: arm64

      - name: Start Pi Emulator
        run: |
          docker-compose -f firmware/docker/docker-compose.yml up -d
          sleep 30  # Wait for emulator to be ready

      - name: Run E2E Tests
        run: |
          docker-compose -f firmware/docker/docker-compose.yml \
            run test-runner pnpm test:e2e

      - name: Collect Logs
        if: failure()
        run: docker-compose logs > e2e-logs.txt

      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: e2e-logs
          path: e2e-logs.txt
```

## Testing Strategy

Following Google's test pyramid (80/15/5):

| Layer                 | Coverage                      | Focus                                                  |
| --------------------- | ----------------------------- | ------------------------------------------------------ |
| **Unit** (80%)        | Individual functions, classes | Hardware detection, config generation, chirp algorithm |
| **Integration** (15%) | Component interactions        | Shairport-sync wrapper, WebSocket API, mDNS            |
| **E2E** (5%)          | Full system                   | Installation, update flow, calibration                 |

### The Beyoncé Rule

> _"If you liked it then you should have put a test on it."_

Every feature that ships **must** have:

1. Unit tests covering core logic
2. Integration tests for external boundaries
3. At least one E2E test proving it works in production-like environment

**Example**: OTA Updates

```typescript
// Unit: checksum verification
it('validates SHA256 correctly', () => { ... });

// Integration: GitHub API interaction
it('fetches release metadata from GitHub', async () => { ... });

// E2E: full update cycle
it('updates from v1.0.0 to v1.1.0 and recovers on failure', async () => { ... });
```

---

## Acceptance Criteria

Phase 1 is complete when:

- [ ] Pi emulator runs locally with `docker-compose up`
- [ ] Installation script succeeds on fresh Debian Bookworm
- [ ] Hardware detection correctly identifies capable systems (Pi 4 1GB+, Pi 5)
- [ ] Installation fails gracefully on unsupported hardware (Pi Zero W, Pi Zero 2 W, Pi 3)
- [ ] AirPlay 2 receiver appears in iOS Control Center with high-quality audio
- [ ] Multi-room sync and stereo pairing work out of the box
- [ ] iOS app discovers and pairs with receiver
- [ ] Latency calibration measures delay within ±5ms accuracy
- [ ] All tests pass in CI (unit, integration, E2E)
- [ ] 80%+ code coverage on critical paths

---

## Multi-Room Audio Support

**Multi-room sync and stereo pairing are natively supported** through shairport-sync's AirPlay 2 implementation. Users can create speaker groups and stereo pairs directly from iOS Control Center without any additional configuration.

This includes:

- **Multi-room sync**: Play the same audio on multiple AirSync receivers simultaneously
- **Stereo pairing**: Pair two receivers as left/right channels
- **Volume control**: Independent or grouped volume adjustment
- **Seamless handoff**: Move audio between rooms

No additional Phase 1 work is required for these features - they work out of the box via AirPlay 2.

---

## Future Considerations (Not in Scope)

These features are explicitly **out of scope** for Phase 1 but the architecture is designed to support future extensions through:

- Modular package structure (easy to add new modules later)
- Extensible protocol definitions
- Hardware capability detection system (can be expanded for new features)

---

## Getting Started

```bash
# Clone the repository
git clone https://github.com/JackDarnell/airsync.git
cd airsync

# Install dependencies
pnpm install

# Start development environment
cd firmware/docker
docker-compose up -d

# Run all tests
pnpm test

# Start receiver in development mode
pnpm dev --filter=receiver-core
```
