# BoxCutter - Manual Xcode Setup

The main app builds and runs. The following manual steps are needed to complete the privileged helper daemon integration and file association.

## 1. Create Helper Command Line Tool Target

1. In Xcode: **File > New > Target > macOS > Command Line Tool**
2. Product Name: `com.hwxnnn.BoxCutter.Helper`
3. Bundle Identifier: `com.hwxnnn.BoxCutter.Helper`
4. Language: Swift

## 2. Add Source Files to Helper Target

The helper source files are at `Helper/` in the project root:
- `Helper/main.swift`
- `Helper/HelperDelegate.swift`
- `Helper/InstallerRunner.swift`

1. Drag these 3 Swift files into the helper target's group in the project navigator
2. When prompted, ensure they are added to the **helper target only** (uncheck BoxCutter)

## 3. Add Shared Files to Both Targets

The shared XPC protocol files are at `Shared/` in the project navigator:
- `Shared/SharedConstants.swift`
- `Shared/HelperProtocol.swift`
- `Shared/ProgressProtocol.swift`

1. Select each file in the project navigator
2. In the **File Inspector** (right sidebar), check both:
   - `BoxCutter` target
   - `com.hwxnnn.BoxCutter.Helper` target

## 4. Embed Helper in Main App Bundle

1. Select the **BoxCutter** target > **Build Phases**
2. Click **+** > **New Copy Files Phase**
3. Set:
   - Destination: **Wrapper**
   - Subpath: `Contents/Library/LaunchDaemons`
4. Click **+** under the copy files list, add the `com.hwxnnn.BoxCutter.Helper` product

## 5. Copy LaunchDaemon Plist

In the same or a new Copy Files phase:
1. Destination: **Wrapper**
2. Subpath: `Contents/Library/LaunchDaemons`
3. Add `Helper/com.hwxnnn.BoxCutter.Helper.plist`

## 6. Configure Document Types (File Association)

1. Select the **BoxCutter** target > **Info** tab
2. Under **Document Types**, click **+** and add:
   - Name: `Installer Package`
   - Types: `com.apple.installer-package-archive`, `com.apple.installer-package`
   - Role: `Viewer`
   - Handler Rank: `Alternate`

## 7. Disable App Sandbox

The main app spawns child processes (`pkgutil`, `installer` for inspection) and communicates with a privileged LaunchDaemon via XPC. The default App Sandbox blocks both.

1. Select the **BoxCutter** target > **Build Settings**
2. Search for "App Sandbox"
3. Set **Enable App Sandbox** to **No**

Alternatively, if you want to keep the sandbox, you'd need to add exceptions for process execution and Mach service lookup, which is complex and not recommended for this app.

## 8. Set Deployment Target

Both targets should have:
- macOS Deployment Target: **15.0**

## 9. Code Signing

Both the main app and helper must be signed with the same team:
- Select each target > **Signing & Capabilities**
- Enable **Automatically manage signing**
- Select your development team

The helper needs to run as root, so proper code signing is essential for SMAppService registration.

**Important:** Update the team ID in `Helper/HelperDelegate.swift` — find the `TEAMID` placeholder in the `validateClient` method and replace it with your actual Apple Developer Team ID.
