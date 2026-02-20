# DMG Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let BoxCutter accept `.dmg` files, mount them, show discovered `.app` bundles with icons and sizes, allow multi-select installation to `/Applications` with per-app progress bars, and offer Open/Show/Done actions on completion.

**Architecture:** Extend the existing `AppState` enum with DMG-specific cases (`dmgReady`, `dmgInstalling`, `dmgCompleted`). Add a `DMGInfo` model for DMG metadata and a `DMGService` namespace for mount/unmount/copy operations. New views (`DMGAppInfoView`, `DMGInstallingView`) follow the same pinned-header + action-bar pattern used by `PackageInfoView`. The existing `CompletionView` gains optional action callbacks for Open App and Show in Finder.

**Tech Stack:** SwiftUI, Foundation (FileManager, Process), AppKit (NSWorkspace for icons/launching), `hdiutil` CLI for mount/unmount, `ditto` CLI for app copying with progress.

---

### Task 1: Create DMGInfo model

**Files:**
- Create: `BoxCutter/BoxCutter/Models/DMGInfo.swift`

**Step 1: Create the model file**

```swift
import Foundation

struct DMGAppEntry: Equatable, Identifiable {
    var id: URL { appURL }

    let appURL: URL
    let appName: String
    let bundleIdentifier: String
    let appSize: Int64
    let fileCount: Int
}

struct DMGInfo: Equatable {
    let dmgURL: URL
    let dmgFileName: String
    let mountPoint: URL
    var apps: [DMGAppEntry]
    var selectedAppIDs: Set<URL>
}

struct InstalledApp: Equatable, Identifiable {
    var id: URL { installedURL }

    let appName: String
    let installedURL: URL
    let bundleIdentifier: String
}
```

Add to Xcode project group `BoxCutter/Models/`.

**Step 2: Build**

Build the project. Expected: compiles with no errors.

**Step 3: Commit**

```
feat: add DMGInfo, DMGAppEntry, InstalledApp models
```

---

### Task 2: Add DMG states to AppState

**Files:**
- Modify: `BoxCutter/BoxCutter/Models/AppState.swift`

**Step 1: Add the new cases**

Replace the entire file:

```swift
import Foundation

enum AppState: Equatable {
    case idle
    case inspecting(URL)
    case packageReady(PackageInfo)
    case installing(PackageInfo)
    case completed(PackageInfo)
    case failed(PackageInfo, errorMessage: String)

    // DMG flow
    case dmgMounting(URL)
    case dmgReady(DMGInfo)
    case dmgInstalling(DMGInfo)
    case dmgCompleted([InstalledApp])
    case dmgFailed(errorMessage: String)
}
```

**Step 2: Build**

Build the project. Expected: errors in `ContentView.swift` switch statement (non-exhaustive). This is expected — later tasks fix it.

**Step 3: Commit**

```
feat: add DMG states to AppState enum
```

---

### Task 3: Create DMGService

**Files:**
- Create: `BoxCutter/BoxCutter/Services/DMGService.swift`

**Step 1: Create the service**

```swift
import Foundation
import AppKit

enum DMGError: LocalizedError {
    case mountFailed(String)
    case noAppsFound
    case copyFailed(String)
    case unmountFailed(String)

    var errorDescription: String? {
        switch self {
        case .mountFailed(let msg): "Failed to mount DMG: \(msg)"
        case .noAppsFound: "No .app bundles found in DMG."
        case .copyFailed(let msg): "Failed to copy app: \(msg)"
        case .unmountFailed(let msg): "Failed to unmount DMG: \(msg)"
        }
    }
}

enum DMGService {

    // MARK: - Mount / Unmount

    static func mount(url: URL) async throws -> URL {
        let (output, status) = await runProcess(
            "/usr/bin/hdiutil",
            arguments: ["attach", url.path, "-nobrowse", "-plist"]
        )
        guard status == 0 else {
            throw DMGError.mountFailed(output)
        }
        guard let mountPoint = parseMountPoint(from: output) else {
            throw DMGError.mountFailed("Could not determine mount point.")
        }
        return URL(fileURLWithPath: mountPoint)
    }

    static func unmount(mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - App Discovery

    static func findApps(at mountPoint: URL) throws -> [DMGAppEntry] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let apps = contents
            .filter { $0.pathExtension.lowercased() == "app" }
            .compactMap { appEntry(at: $0) }
        guard !apps.isEmpty else { throw DMGError.noAppsFound }
        return apps.sorted { $0.appSize > $1.appSize }
    }

    private static func appEntry(at url: URL) -> DMGAppEntry? {
        let name = url.deletingPathExtension().lastPathComponent
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        let bundleID: String
        if let dict = NSDictionary(contentsOf: plistURL),
           let id = dict["CFBundleIdentifier"] as? String {
            bundleID = id
        } else {
            bundleID = ""
        }
        let size = directorySize(at: url)
        let fileCount = Self.fileCount(at: url)
        return DMGAppEntry(
            appURL: url,
            appName: name,
            bundleIdentifier: bundleID,
            appSize: size,
            fileCount: fileCount
        )
    }

    // MARK: - Copy App to /Applications

    /// Copies an app bundle to /Applications using `ditto`, reporting progress
    /// based on file count. Returns the installed URL on success.
    static func copyApp(
        from source: DMGAppEntry,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let destination = URL(fileURLWithPath: "/Applications/\(source.appName).app")
        let fm = FileManager.default

        // Remove existing copy if present
        if fm.fileExists(atPath: destination.path) {
            try? fm.trashItem(at: destination, resultingItemURL: nil)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
        }

        let totalFiles = source.fileCount
        var copiedFiles = 0

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-V", source.appURL.path, destination.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let str = String(data: data, encoding: .utf8) else { return }
                let lines = str.components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }
                copiedFiles += lines.count
                let pct = totalFiles > 0
                    ? min(Double(copiedFiles) / Double(totalFiles), 0.99)
                    : 0
                Task { @MainActor in onProgress(pct) }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in onProgress(1.0) }
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: destination)
                } else {
                    continuation.resume(
                        throwing: DMGError.copyFailed(
                            "ditto exited with code \(proc.terminationStatus)"
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: DMGError.copyFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Helpers

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private static func fileCount(at url: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var count = 0
        for _ in enumerator { count += 1 }
        return count
    }

    private static func runProcess(
        _ path: String,
        arguments: [String]
    ) async -> (String, Int32) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, process.terminationStatus))
            } catch {
                continuation.resume(returning: (error.localizedDescription, -1))
            }
        }
    }

    private static func parseMountPoint(from plistOutput: String) -> String? {
        guard let data = plistOutput.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            return nil
        }
        return entities
            .compactMap { $0["mount-point"] as? String }
            .first
    }
}
```

Add to Xcode project group `BoxCutter/Services/`.

**Step 2: Build**

Build the project. Expected: compiles with no errors (plus the pre-existing ContentView switch errors from Task 2).

**Step 3: Commit**

```
feat: add DMGService for mount, unmount, app discovery, and copy
```

---

### Task 4: Update DropZoneView for DMG support

**Files:**
- Modify: `BoxCutter/BoxCutter/Views/DropZoneView.swift`

**Step 1: Accept both `.pkg` and `.dmg` extensions**

Change the text from `"Drop .pkg here"` to `"Drop .pkg or .dmg here"`:

```swift
Text("Drop .pkg or .dmg here")
```

Change the drop handler filter on line 40 from:

```swift
url.pathExtension.lowercased() == "pkg" else { return }
```

to:

```swift
["pkg", "dmg"].contains(url.pathExtension.lowercased()) else { return }
```

**Step 2: Commit**

```
feat: accept .dmg files in DropZoneView
```

---

### Task 5: Update AppDelegate and file picker for DMG support

**Files:**
- Modify: `BoxCutter/BoxCutter/BoxCutterApp.swift`
- Modify: `BoxCutter/BoxCutter/ViewModels/AppViewModel.swift`

**Step 1: Rename notification and handle DMG in AppDelegate**

In `BoxCutterApp.swift`, rename the notification:

```swift
extension Notification.Name {
    static let openFile = Notification.Name("openFile")
}
```

Update `AppDelegate`:

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "pkg" || ext == "dmg" {
                NotificationCenter.default.post(name: .openFile, object: url)
            }
        }
    }
}
```

**Step 2: Update Info.plist to register DMG document type**

In `BoxCutter/BoxCutter/Info.plist`, add a second document type dict inside the `CFBundleDocumentTypes` array:

```xml
<dict>
    <key>CFBundleTypeIconSystemGenerated</key>
    <true/>
    <key>CFBundleTypeName</key>
    <string>Disk Image</string>
    <key>CFBundleTypeRole</key>
    <string>Viewer</string>
    <key>LSHandlerRank</key>
    <string>Alternate</string>
    <key>LSItemContentTypes</key>
    <array>
        <string>com.apple.disk-image-udif</string>
    </array>
</dict>
```

**Step 3: Update file picker in AppViewModel to accept DMG**

In `AppViewModel.swift`, change `selectFile()`:

```swift
func selectFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [
        UTType(filenameExtension: "pkg")!,
        UTType(filenameExtension: "dmg")!
    ]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url {
        handleFile(url: url)
    }
}
```

**Step 4: Commit**

```
feat: register DMG document type, update AppDelegate and file picker
```

---

### Task 6: Add DMG flow to AppViewModel

**Files:**
- Modify: `BoxCutter/BoxCutter/ViewModels/AppViewModel.swift`

**Step 1: Add DMG state properties**

After the existing properties (line 15), add:

```swift
var dmgInstallProgress: [URL: Double] = [:]
private var currentMountPoint: URL?
```

**Step 2: Add `handleFile` dispatch method**

After `loadPackage(url:)`, add:

```swift
func handleFile(url: URL) {
    if url.pathExtension.lowercased() == "dmg" {
        loadDMG(url: url)
    } else {
        loadPackage(url: url)
    }
}
```

**Step 3: Add DMG lifecycle methods**

After `handleFile`, add:

```swift
// MARK: - DMG Flow

func loadDMG(url: URL) {
    state = .dmgMounting(url)
    Task {
        do {
            let mountPoint = try await DMGService.mount(url: url)
            currentMountPoint = mountPoint
            let apps = try DMGService.findApps(at: mountPoint)
            let info = DMGInfo(
                dmgURL: url,
                dmgFileName: url.lastPathComponent,
                mountPoint: mountPoint,
                apps: apps,
                selectedAppIDs: apps.count == 1
                    ? Set([apps[0].appURL])
                    : Set()
            )
            state = .dmgReady(info)
        } catch {
            if let mp = currentMountPoint {
                DMGService.unmount(mountPoint: mp)
                currentMountPoint = nil
            }
            state = .dmgFailed(errorMessage: error.localizedDescription)
        }
    }
}

func toggleAppSelection(_ app: DMGAppEntry) {
    guard case .dmgReady(var info) = state else { return }
    if info.selectedAppIDs.contains(app.appURL) {
        info.selectedAppIDs.remove(app.appURL)
    } else {
        info.selectedAppIDs.insert(app.appURL)
    }
    state = .dmgReady(info)
}

func installSelectedApps() {
    guard case .dmgReady(let info) = state else { return }
    let selected = info.apps.filter { info.selectedAppIDs.contains($0.appURL) }
    guard !selected.isEmpty else { return }

    state = .dmgInstalling(info)
    dmgInstallProgress = Dictionary(uniqueKeysWithValues: selected.map { ($0.appURL, 0.0) })

    Task {
        var installed: [InstalledApp] = []
        var errors: [String] = []

        await withTaskGroup(of: Result<InstalledApp, Error>.self) { group in
            for app in selected {
                group.addTask {
                    do {
                        let dest = try await DMGService.copyApp(from: app) { pct in
                            Task { @MainActor in
                                self.dmgInstallProgress[app.appURL] = pct
                            }
                        }
                        return .success(InstalledApp(
                            appName: app.appName,
                            installedURL: dest,
                            bundleIdentifier: app.bundleIdentifier
                        ))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let app): installed.append(app)
                case .failure(let error): errors.append(error.localizedDescription)
                }
            }
        }

        // Unmount and optionally trash
        DMGService.unmount(mountPoint: info.mountPoint)
        currentMountPoint = nil

        if settings.trashAfterInstall {
            try? FileManager.default.trashItem(at: info.dmgURL, resultingItemURL: nil)
        }

        if !installed.isEmpty {
            if settings.playSoundOnComplete {
                NSSound(named: NSSound.Name(settings.completionSound))?.play()
            }
            state = .dmgCompleted(installed)

            if settings.autoCloseAfterInstall {
                try? await Task.sleep(for: .seconds(settings.autoCloseDelay))
                NSApplication.shared.terminate(nil)
            }
        } else {
            if settings.playSoundOnComplete {
                NSSound(named: NSSound.Name("Basso"))?.play()
            }
            state = .dmgFailed(errorMessage: errors.joined(separator: "\n"))
        }
    }
}

func showDMGInFinder() {
    guard case .dmgReady(let info) = state else { return }
    NSWorkspace.shared.open(info.mountPoint)
}

func cancelDMG() {
    if let mp = currentMountPoint {
        DMGService.unmount(mountPoint: mp)
        currentMountPoint = nil
    }
    reset()
}

func openInstalledApp(_ app: InstalledApp) {
    NSWorkspace.shared.open(app.installedURL)
}

func revealInstalledApp(_ app: InstalledApp) {
    NSWorkspace.shared.selectFile(
        app.installedURL.path,
        inFileViewerRootedAtPath: "/Applications"
    )
}
```

**Step 4: Update `reset()` to clear DMG state**

```swift
func reset() {
    if let mp = currentMountPoint {
        DMGService.unmount(mountPoint: mp)
        currentMountPoint = nil
    }
    state = .idle
    outputLines = []
    progress = 0
    showDetails = false
    showLicense = false
    installTarget = "/"
    dmgInstallProgress = [:]
}
```

**Step 5: Update `loadPackage` to use `handleFile`** (optional clean-up)

The existing `loadPackage(url:)` stays as-is. The new `handleFile(url:)` calls it for `.pkg` files.

**Step 6: Commit**

```
feat: add DMG flow methods to AppViewModel
```

---

### Task 7: Create DMGAppInfoView

**Files:**
- Create: `BoxCutter/BoxCutter/Views/DMGAppInfoView.swift`

**Step 1: Create the view**

```swift
import SwiftUI
import AppKit

struct DMGAppInfoView: View {

    let info: DMGInfo
    let onCancel: () -> Void
    let onInstall: () -> Void
    let onShow: () -> Void
    let onToggleApp: (DMGAppEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            appList
                .padding(16)

            Divider()
                .padding(.horizontal, 16)

            actionBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    // MARK: - App List

    private var appList: some View {
        VStack(spacing: 8) {
            ForEach(info.apps) { app in
                appRow(app)
            }
        }
    }

    private func appRow(_ app: DMGAppEntry) -> some View {
        let isSelected = info.selectedAppIDs.contains(app.appURL)
        return HStack(spacing: 10) {
            // Checkbox for multi-app DMGs
            if info.apps.count > 1 {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .tertiary)
                    .font(.body)
                    .onTapGesture { onToggleApp(app) }
            }

            // App icon
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                .resizable()
                .frame(width: 32, height: 32)

            // App info
            VStack(alignment: .leading, spacing: 3) {
                Text(app.appName)
                    .font(.headline)
                    .lineLimit(1)

                Text(formattedSize(app.appSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if info.apps.count > 1 {
                onToggleApp(app)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)

            Button("Show in Finder") { onShow() }

            Button("Install") { onInstall() }
                .keyboardShortcut(.defaultAction)
                .disabled(info.selectedAppIDs.isEmpty)
        }
    }

    // MARK: - Helpers

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview("Single App") {
    DMGAppInfoView(
        info: DMGInfo(
            dmgURL: URL(fileURLWithPath: "/tmp/Example.dmg"),
            dmgFileName: "Example.dmg",
            mountPoint: URL(fileURLWithPath: "/Volumes/Example"),
            apps: [
                DMGAppEntry(
                    appURL: URL(fileURLWithPath: "/Volumes/Example/MyApp.app"),
                    appName: "MyApp",
                    bundleIdentifier: "com.example.myapp",
                    appSize: 125_000_000,
                    fileCount: 3200
                )
            ],
            selectedAppIDs: [URL(fileURLWithPath: "/Volumes/Example/MyApp.app")]
        ),
        onCancel: {}, onInstall: {}, onShow: {}, onToggleApp: { _ in }
    )
    .frame(width: 400)
}
```

Add to Xcode project group `BoxCutter/Views/`.

**Step 2: Commit**

```
feat: add DMGAppInfoView for displaying discovered apps
```

---

### Task 8: Create DMGInstallingView

**Files:**
- Create: `BoxCutter/BoxCutter/Views/DMGInstallingView.swift`

**Step 1: Create the view**

```swift
import SwiftUI
import AppKit

struct DMGInstallingView: View {

    let info: DMGInfo
    let progress: [URL: Double]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(selectedApps) { app in
                let pct = progress[app.appURL] ?? 0
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                        .resizable()
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(app.appName)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            if pct >= 1.0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                Text("\(Int(pct * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        ProgressView(value: pct)
                            .progressViewStyle(.linear)
                    }
                }
            }
        }
        .padding(16)
    }

    private var selectedApps: [DMGAppEntry] {
        info.apps.filter { info.selectedAppIDs.contains($0.appURL) }
    }
}

#Preview {
    DMGInstallingView(
        info: DMGInfo(
            dmgURL: URL(fileURLWithPath: "/tmp/Example.dmg"),
            dmgFileName: "Example.dmg",
            mountPoint: URL(fileURLWithPath: "/Volumes/Example"),
            apps: [
                DMGAppEntry(
                    appURL: URL(fileURLWithPath: "/Volumes/Example/App1.app"),
                    appName: "App1", bundleIdentifier: "com.example.app1",
                    appSize: 50_000_000, fileCount: 1200
                ),
                DMGAppEntry(
                    appURL: URL(fileURLWithPath: "/Volumes/Example/App2.app"),
                    appName: "App2", bundleIdentifier: "com.example.app2",
                    appSize: 80_000_000, fileCount: 2400
                )
            ],
            selectedAppIDs: [
                URL(fileURLWithPath: "/Volumes/Example/App1.app"),
                URL(fileURLWithPath: "/Volumes/Example/App2.app")
            ]
        ),
        progress: [
            URL(fileURLWithPath: "/Volumes/Example/App1.app"): 1.0,
            URL(fileURLWithPath: "/Volumes/Example/App2.app"): 0.45
        ]
    )
    .frame(width: 400)
}
```

Add to Xcode project group `BoxCutter/Views/`.

**Step 2: Commit**

```
feat: add DMGInstallingView with per-app progress bars
```

---

### Task 9: Extend CompletionView for DMG completion

**Files:**
- Modify: `BoxCutter/BoxCutter/Views/CompletionView.swift`

**Step 1: Replace the entire file**

The existing `CompletionView` only has a "Done" button. The DMG completion needs "Done", "Open App", and "Show in Finder". Make the view support optional extra actions:

```swift
import SwiftUI

struct CompletionView: View {

    let success: Bool
    let packageName: String
    let message: String
    let onDone: () -> Void
    var extraActions: [CompletionAction] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(success ? .green : .red)

                VStack(alignment: .leading, spacing: 3) {
                    Text(success ? "Installation Complete" : "Installation Failed")
                        .font(.headline)

                    if success {
                        Text(packageName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }

                Spacer()
            }

            if !extraActions.isEmpty {
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                HStack(spacing: 8) {
                    Spacer()
                    ForEach(extraActions) { action in
                        Button(action.label) { action.handler() }
                    }
                    Button("Done") { onDone() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 10)
            } else {
                HStack {
                    Spacer()
                    Button("Done") { onDone() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 10)
            }
        }
        .padding(16)
    }
}

struct CompletionAction: Identifiable {
    let id = UUID()
    let label: String
    let handler: () -> Void

    static func == (lhs: CompletionAction, rhs: CompletionAction) -> Bool {
        lhs.id == rhs.id
    }
}

#Preview("Success") {
    CompletionView(success: true, packageName: "Example", message: "", onDone: {})
        .frame(width: 400)
}

#Preview("Failure") {
    CompletionView(success: false, packageName: "Example", message: "Exit code 1.", onDone: {})
        .frame(width: 400)
}

#Preview("DMG Complete") {
    CompletionView(
        success: true,
        packageName: "MyApp",
        message: "",
        onDone: {},
        extraActions: [
            CompletionAction(label: "Show in Finder") {},
            CompletionAction(label: "Open App") {}
        ]
    )
    .frame(width: 400)
}
```

**Step 2: Commit**

```
feat: extend CompletionView with optional extra action buttons
```

---

### Task 10: Wire everything in ContentView

**Files:**
- Modify: `BoxCutter/BoxCutter/ContentView.swift`

**Step 1: Update the notification listener and add DMG state cases**

Replace the entire file:

```swift
import SwiftUI

struct ContentView: View {

    @State private var viewModel = AppViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Helper status banner
            if viewModel.helperManager.needsApproval {
                approvalBanner
            } else if !viewModel.helperManager.isHelperInstalled {
                helperBanner
            }

            // Main content based on state
            switch viewModel.state {
            case .idle:
                DropZoneView(
                    onFileDrop: { url in viewModel.handleFile(url: url) },
                    onSelectFile: { viewModel.selectFile() }
                )

            case .inspecting:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)

            case .packageReady(let info):
                PackageInfoView(
                    info: info,
                    onCancel: { viewModel.reset() },
                    onInstall: { viewModel.install(package: info) },
                    showDetails: $viewModel.showDetails,
                    detailsLoading: viewModel.detailsLoading,
                    installTarget: $viewModel.installTarget,
                    showLicense: $viewModel.showLicense
                )

            case .installing(let info):
                InstallingView(
                    packageName: info.packageName.isEmpty ? info.fileName : info.packageName,
                    outputLines: viewModel.outputLines,
                    progress: viewModel.progress,
                    showDetails: $viewModel.showDetails
                )

            case .completed(let info):
                CompletionView(
                    success: true,
                    packageName: info.packageName.isEmpty ? info.fileName : info.packageName,
                    message: "Installation completed successfully.",
                    onDone: { viewModel.reset() }
                )

            case .failed(let info, let errorMessage):
                CompletionView(
                    success: false,
                    packageName: info.packageName.isEmpty ? info.fileName : info.packageName,
                    message: errorMessage,
                    onDone: { viewModel.reset() }
                )

            // DMG states
            case .dmgMounting:
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Mounting disk image\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)

            case .dmgReady(let info):
                DMGAppInfoView(
                    info: info,
                    onCancel: { viewModel.cancelDMG() },
                    onInstall: { viewModel.installSelectedApps() },
                    onShow: { viewModel.showDMGInFinder() },
                    onToggleApp: { app in viewModel.toggleAppSelection(app) }
                )

            case .dmgInstalling(let info):
                DMGInstallingView(
                    info: info,
                    progress: viewModel.dmgInstallProgress
                )

            case .dmgCompleted(let apps):
                dmgCompletionView(apps: apps)

            case .dmgFailed(let errorMessage):
                CompletionView(
                    success: false,
                    packageName: "Disk Image",
                    message: errorMessage,
                    onDone: { viewModel.reset() }
                )
            }
        }
        .frame(width: 400)
        .onAppear {
            AppSettings.shared.applyWindowLevel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { notification in
            if let url = notification.object as? URL {
                viewModel.handleFile(url: url)
            }
        }
    }

    // MARK: - DMG Completion

    private func dmgCompletionView(apps: [InstalledApp]) -> some View {
        let name = apps.count == 1
            ? apps[0].appName
            : "\(apps.count) apps"
        var actions: [CompletionAction] = []
        if let first = apps.first {
            actions.append(CompletionAction(label: "Show in Finder") {
                viewModel.revealInstalledApp(first)
            })
        }
        if apps.count == 1, let only = apps.first {
            actions.append(CompletionAction(label: "Open App") {
                viewModel.openInstalledApp(only)
            })
        }
        return CompletionView(
            success: true,
            packageName: name,
            message: "",
            onDone: { NSApplication.shared.terminate(nil) },
            extraActions: actions
        )
    }

    // MARK: - Banners

    private var approvalBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "gear.badge").foregroundStyle(.orange).font(.caption)
            Text("Helper needs approval.").font(.caption)
            Spacer()
            Button("System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
            }
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.orange.opacity(0.08))
    }

    private var helperBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.caption)
            Text("Helper not installed.").font(.caption)
            Spacer()
            Button("Install") { viewModel.installHelper() }
                .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.yellow.opacity(0.08))
    }
}
```

**Step 2: Build**

Build the project. Expected: compiles with no errors. All PKG flows unchanged.

**Step 3: Commit**

```
feat: wire DMG states into ContentView
```

---

### Task 11: Build, verify, and final commit

**Step 1: Full build**

Build the project. Fix any compile errors.

**Step 2: Manual verification checklist**

- [ ] Drop a `.pkg` file — existing flow works unchanged
- [ ] Drop a `.dmg` file — mounts, shows app(s), Install/Show/Cancel visible
- [ ] Single-app DMG auto-selects the app
- [ ] Multi-app DMG shows checkboxes, allows multi-select
- [ ] "Show in Finder" opens the mounted DMG volume
- [ ] "Cancel" unmounts and returns to idle
- [ ] "Install" copies selected apps to `/Applications` with progress bars
- [ ] After install: DMG unmounted, DMG trashed (if setting enabled)
- [ ] Completion screen shows "Open App" and "Show in Finder" and "Done"
- [ ] "Done" quits the app
- [ ] "Open App" launches the installed app
- [ ] "Show in Finder" reveals the app in `/Applications`
- [ ] File picker shows both `.pkg` and `.dmg` file types
- [ ] Double-clicking a `.dmg` in Finder opens BoxCutter (after setting it as handler)

**Step 3: Final commit**

```
feat: complete DMG support with multi-app install and progress tracking
```
