# BoxCutter Design

Alternative macOS package installer that replaces the default Package Installer with a clean, minimal, native SwiftUI app.

## Requirements

- Receive .pkg files via Finder double-click, drag-and-drop, or file picker
- Display detailed package information and ask for user confirmation before install
- Install using the `installer` CLI tool with realtime verbose output
- Persistent root privilege via a privileged helper daemon (no password prompt per install)
- macOS 15 Sequoia minimum

## Architecture

### Targets

1. **BoxCutter** — Main SwiftUI app
2. **com.hwxnnn.BoxCutter.Helper** — Privileged LaunchDaemon (command-line tool target, runs as root)
3. **BoxCutterShared** — Shared XPC protocol definition

### Privileged Helper (SMAppService Daemon)

- Registered via `SMAppService.daemon(plistName:)` (macOS 13+ API)
- Runs as root via launchd
- Main app communicates via `NSXPCConnection` using a shared `@objc` protocol
- Helper receives .pkg path, runs `installer -verboseR -pkg <path> -target /`, streams output back over XPC
- Helper validates connecting app's code signature (team ID check)
- Helper only accepts absolute paths to `.pkg` files

### XPC Protocol

```swift
@objc protocol HelperProtocol {
    func installPackage(
        atPath path: String,
        withReply reply: @escaping (Bool, String) -> Void
    )
    func streamOutput(
        _ handler: @escaping (String) -> Void
    )
}
```

## UI Flow

Single window with four states managed by an `AppState` enum:

### State 1: Idle (Drop Zone)

- Centered drop zone with dashed border and package icon
- "Drop a .pkg file here" text with "Select File..." button
- Accepts Finder double-click (registered UTI for `com.apple.installer-package-archive`)
- Banner at top if helper not installed: "Helper not installed — Install Helper"

### State 2: Package Info / Confirm

- Header: package icon + filename
- Info grid:
  - Package name & bundle identifier
  - Version
  - File size
  - Install location (`/`)
  - Signing status (signed/unsigned + certificate name)
  - Number of payloads
  - Pre/post-install scripts presence (warning icon if present)
  - Scrollable list of files to be installed
- Bottom bar: "Cancel" (returns to idle) and "Install" button (prominent)

### State 3: Installing

- Header: "Installing [package name]..."
- Monospaced scrollable text view with realtime verbose log (auto-scrolls)
- Progress bar parsed from `installer -verboseR` percent output lines
- No cancel (installer doesn't support graceful cancellation)

### State 4: Complete / Error

- Success: checkmark icon, "Installation Complete", "Done" button
- Error: error icon, "Installation Failed" with error message, "Done" button
- "Done" returns to idle state

## Package Inspection

Metadata extraction (runs as current user, no root needed):

| Info | Command |
|------|---------|
| Name, identifier, version, location | `installer -pkginfo -pkg <path>` |
| Signing & certificate chain | `pkgutil --check-signature <path>` |
| Payload file list | `pkgutil --payload-files <path>` |
| Pre/post-install scripts | `pkgutil --expand <path> <tmpdir>`, check for scripts |
| File size | `FileManager.default.attributesOfItem` |

## File Association & Entry Points

Three intake methods, all funnel to `loadPackage(url:)`:

1. **Finder double-click** — UTType `com.apple.installer-package-archive` in Info.plist, handled via `NSApplicationDelegateAdaptor` with `application(_:open:)`
2. **Drag and drop** — `.onDrop(of:)` on drop zone, filtered to `.pkg` UTType
3. **File picker** — `NSOpenPanel` filtered to `.pkg` files

## Security

- Helper validates connecting client's code signature
- Only absolute `.pkg` file paths accepted (no path traversal)
- Helper only executes `/usr/sbin/installer`, nothing else
- Pre/post-install script warnings shown to user before confirmation
