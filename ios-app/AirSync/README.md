# AirSync iOS Library

Swift package for discovering and connecting to AirSync AirPlay receivers on the local network.

## Features

- ✅ **mDNS/Bonjour Discovery** - Finds AirPlay receivers automatically
- ✅ **Real-time Updates** - Receivers appear/disappear as they come online
- ✅ **SwiftUI Support** - Ready-to-use views with Combine integration
- ✅ **TDD Development** - 14/15 tests passing
- ✅ **iOS 13+** - Supports iOS 13, macOS 10.15+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/JackDarnell/Airsync-Platform.git", from: "0.1.0")
]
```

Or in Xcode:
1. File → Add Packages...
2. Enter repository URL
3. Select version

### Local Development

```bash
cd ios-app/AirSync
swift build
swift test
```

## Quick Start

### Basic Discovery

```swift
import AirSync

let discovery = ReceiverDiscovery()

// Start discovering receivers
discovery.startDiscovery()

// Observe receivers
discovery.$receivers
    .sink { receivers in
        print("Found \(receivers.count) receivers")
        receivers.forEach { receiver in
            print("- \(receiver.displayName) at \(receiver.hostname):\(receiver.port)")
        }
    }
    .store(in: &cancellables)

// Stop discovery when done
discovery.stopDiscovery()
```

### SwiftUI Integration

```swift
import SwiftUI
import AirSync

struct ContentView: View {
    var body: some View {
        ReceiverListView()
    }
}
```

That's it! The view automatically:
- Starts discovery when it appears
- Shows a loading state while searching
- Lists all discovered receivers
- Stops discovery when dismissed

### Custom UI

```swift
import SwiftUI
import AirSync

struct MyReceiverList: View {
    @StateObject private var discovery = ReceiverDiscovery()

    var body: some View {
        List(discovery.receivers) { receiver in
            HStack {
                VStack(alignment: .leading) {
                    Text(receiver.displayName)
                        .font(.headline)
                    Text("\(receiver.hostname):\(receiver.port)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if discovery.isDiscovering {
                    ProgressView()
                }
            }
        }
        .onAppear {
            discovery.startDiscovery()
        }
        .onDisappear {
            discovery.stopDiscovery()
        }
    }
}
```

## Testing

### Run Unit Tests

```bash
swift test
```

**Current status:** 14/15 tests passing
- 7/7 Receiver model tests ✅
- 7/8 ReceiverDiscovery tests ✅
  - 1 integration test requires local Docker container (optional)

### Test with Real Hardware

1. **Start local AirSync receiver:**
   ```bash
   cd ../../docker/local-testing
   bash test-local.sh
   ```

2. **Run tests:**
   ```bash
   swift test
   ```

3. **Or test in iOS Simulator:**
   - Run your app in Simulator
   - ReceiverListView should show "AirSync Local Test"

## API Reference

### ReceiverDiscovery

Main service for discovering AirPlay receivers.

```swift
public class ReceiverDiscovery: ObservableObject {
    /// List of discovered receivers
    @Published public private(set) var receivers: [Receiver]

    /// Whether discovery is active
    @Published public private(set) var isDiscovering: Bool

    /// mDNS service type
    public let serviceType: String = "_airplay._tcp"

    /// Start discovering receivers
    public func startDiscovery()

    /// Stop discovering and clear receivers
    public func stopDiscovery()
}
```

### Receiver

Model representing a discovered AirPlay receiver.

```swift
public struct Receiver: Identifiable, Equatable, Hashable {
    /// Unique identifier for SwiftUI
    public let id: UUID

    /// User-friendly name
    public let name: String

    /// Network hostname
    public let hostname: String

    /// Port number
    public let port: Int

    /// Display name (name or hostname)
    public var displayName: String
}
```

### ReceiverListView

SwiftUI view for displaying receivers.

```swift
public struct ReceiverListView: View {
    public init(discovery: ReceiverDiscovery = ReceiverDiscovery())
}
```

## Architecture

```
┌──────────────────────────────────────┐
│         iOS App                      │
│                                      │
│  ┌────────────────────────────────┐  │
│  │   ReceiverListView (SwiftUI)   │  │
│  └───────────┬────────────────────┘  │
│              │                       │
│              ▼                       │
│  ┌────────────────────────────────┐  │
│  │   ReceiverDiscovery            │  │
│  │   (ObservableObject)           │  │
│  │                                │  │
│  │   Uses:                        │  │
│  │   - NWBrowser (mDNS)           │  │
│  │   - Combine (@Published)       │  │
│  └────────────────────────────────┘  │
│              │                       │
│              ▼                       │
│      Local Network                   │
└──────────────────────────────────────┘
         │
         │ mDNS (_airplay._tcp)
         ▼
┌──────────────────────────────────────┐
│   AirPlay Receivers                  │
│   - AirSync Local Test (Docker)      │
│   - Raspberry Pi Receivers           │
│   - Orange Pi Receivers              │
└──────────────────────────────────────┘
```

## Development

### TDD Workflow

This project follows strict TDD:

1. **RED** - Write failing test
2. **GREEN** - Write minimal code to pass
3. **REFACTOR** - Clean up while keeping tests green

Example workflow:

```bash
# 1. Write test (RED)
# Edit Tests/AirSyncTests/ReceiverTests.swift

# 2. Run test (should fail)
swift test

# 3. Implement feature (GREEN)
# Edit Sources/AirSync/Receiver.swift

# 4. Run test (should pass)
swift test

# 5. Refactor if needed
# 6. Repeat
```

### Adding New Features

1. Write tests first in `Tests/AirSyncTests/`
2. Run `swift test` to verify they fail
3. Implement in `Sources/AirSync/`
4. Run `swift test` to verify they pass
5. Submit PR with all tests passing

## Requirements

- iOS 13.0+ / macOS 10.15+
- Swift 5.9+
- Xcode 15+

## Permissions

Your app needs network permissions to discover receivers. Add to `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>AirSync needs to discover AirPlay receivers on your local network</string>

<key>NSBonjourServices</key>
<array>
    <string>_airplay._tcp</string>
</array>
```

## Troubleshooting

### No Receivers Found

1. **Check network permissions** - iOS may block local network access
2. **Verify receiver is running:**
   ```bash
   dns-sd -B _airplay._tcp local.
   ```
3. **Same network** - Device and receiver must be on same WiFi/LAN
4. **Firewall** - Check if firewall blocks mDNS (port 5353)

### Discovery Fails

1. **Check logs** - Look for error messages in console
2. **Restart discovery:**
   ```swift
   discovery.stopDiscovery()
   discovery.startDiscovery()
   ```
3. **Test with Docker:**
   ```bash
   cd docker/local-testing && bash test-local.sh
   ```

### Tests Fail

```bash
# Clean and rebuild
rm -rf .build
swift build
swift test
```

## Examples

### Monitor Discovery State

```swift
discovery.$isDiscovering
    .sink { isDiscovering in
        if isDiscovering {
            print("🔍 Searching...")
        } else {
            print("⏹️ Stopped")
        }
    }
    .store(in: &cancellables)
```

### Filter Receivers

```swift
let airSyncReceivers = discovery.receivers.filter { receiver in
    receiver.name.contains("AirSync")
}
```

### React to Receiver Changes

```swift
discovery.$receivers
    .removeDuplicates()
    .sink { receivers in
        print("Receivers updated: \(receivers.count) found")
    }
    .store(in: &cancellables)
```

## Related Documentation

- [Local Testing Guide](../../docker/local-testing/README.md) - Test with Docker
- [Main README](../../README.md) - Project overview
- [Installation Guide](../../installer/README.md) - Install on Raspberry Pi

## License

[License information to be added]

## Support

For issues and questions, please use GitHub Issues.
