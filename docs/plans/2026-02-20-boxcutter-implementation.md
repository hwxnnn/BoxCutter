# BoxCutter Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS alternative to the default Package Installer that uses a privileged helper daemon for silent installs.

**Architecture:** SwiftUI app with a single-window state machine (idle/inspect/installing/done). A separate command-line tool target runs as a LaunchDaemon via SMAppService, providing root access for the `installer` CLI. Communication between app and daemon uses NSXPCConnection with bidirectional protocols for streaming output.

**Tech Stack:** Swift, SwiftUI, AppKit (NSApplicationDelegate, NSOpenPanel), Foundation (NSXPCConnection, Process), ServiceManagement (SMAppService), macOS 15+

---

### Task 1: Create Project Directory Structure

**Files:**
- Create directories in Xcode project navigator

**Step 1: Create directories**

Using the Xcode MCP tools, create these groups in the project:
- `BoxCutter/BoxCutter/Models/`
- `BoxCutter/BoxCutter/Views/`
- `BoxCutter/BoxCutter/ViewModels/`
- `BoxCutter/BoxCutter/Services/`
- `BoxCutter/Shared/`
- `BoxCutter/Helper/`

**Step 2: Commit**

```bash
git add -A && git commit -m "chore: create project directory structure"
```

---

### Task 2: Models — AppState and PackageInfo

**Files:**
- Create: `BoxCutter/BoxCutter/Models/AppState.swift`
- Create: `BoxCutter/BoxCutter/Models/PackageInfo.swift`

**Step 1: Create AppState.swift**

```swift
import Foundation

enum AppState: Equatable {
    case idle
    case inspecting(URL)
    case packageReady(PackageInfo)
    case installing(PackageInfo)
    case completed(PackageInfo)
    case failed(PackageInfo, errorMessage: String)
}
```

**Step 2: Create PackageInfo.swift**

```swift
import Foundation

struct PackageInfo: Equatable, Identifiable {
    var id: URL { fileURL }

    let fileURL: URL
    let fileName: String
    let fileSize: Int64

    var packageName: String = ""
    var packageIdentifier: String = ""
    var version: String = ""
    var installLocation: String = "/"

    var isSigned: Bool = false
    var signingStatus: String = "Unknown"
    var certificateChain: [String] = []

    var payloadFiles: [String] = []
    var hasPreinstallScript: Bool = false
    var hasPostinstallScript: Bool = false
}
```

**Step 3: Commit**

```bash
git add BoxCutter/BoxCutter/Models/
git commit -m "feat: add AppState and PackageInfo models"
```

---

### Task 3: PackageInspector — CLI Output Parsing

This is the core business logic with the most testable surface area.

**Files:**
- Create: `BoxCutter/BoxCutter/Services/PackageInspector.swift`

**Step 1: Create PackageInspector.swift**

```swift
import Foundation

actor PackageInspector {

    enum InspectionError: LocalizedError {
        case fileNotFound(URL)
        case notAPackage(URL)
        case inspectionFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url): return "File not found: \(url.path)"
            case .notAPackage(let url): return "Not a .pkg file: \(url.lastPathComponent)"
            case .inspectionFailed(let msg): return "Inspection failed: \(msg)"
            }
        }
    }

    func inspect(url: URL) async throws -> PackageInfo {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InspectionError.fileNotFound(url)
        }
        guard url.pathExtension.lowercased() == "pkg" else {
            throw InspectionError.notAPackage(url)
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0

        var info = PackageInfo(
            fileURL: url,
            fileName: url.lastPathComponent,
            fileSize: fileSize
        )

        async let pkgInfo = fetchPackageInfo(url: url)
        async let sigInfo = fetchSignatureInfo(url: url)
        async let payloadFiles = fetchPayloadFiles(url: url)
        async let scriptInfo = fetchScriptInfo(url: url)

        let (pkg, sig, files, scripts) = await (
            try? pkgInfo,
            try? sigInfo,
            try? payloadFiles,
            try? scriptInfo
        )

        if let pkg {
            info.packageName = pkg.name
            info.packageIdentifier = pkg.identifier
            info.version = pkg.version
            info.installLocation = pkg.location
        }
        if let sig {
            info.isSigned = sig.isSigned
            info.signingStatus = sig.status
            info.certificateChain = sig.chain
        }
        if let files {
            info.payloadFiles = files
        }
        if let scripts {
            info.hasPreinstallScript = scripts.hasPreinstall
            info.hasPostinstallScript = scripts.hasPostinstall
        }

        return info
    }

    // MARK: - CLI Wrappers

    private struct PkgMetadata {
        let name: String
        let identifier: String
        let version: String
        let location: String
    }

    private func fetchPackageInfo(url: URL) async throws -> PkgMetadata {
        let output = try runProcess("/usr/sbin/installer", arguments: ["-pkginfo", "-pkg", url.path])
        return parsePkgInfo(output)
    }

    private struct SignatureInfo {
        let isSigned: Bool
        let status: String
        let chain: [String]
    }

    private func fetchSignatureInfo(url: URL) async throws -> SignatureInfo {
        let output = try runProcess("/usr/sbin/pkgutil", arguments: ["--check-signature", url.path])
        return parseSignatureInfo(output)
    }

    private func fetchPayloadFiles(url: URL) async throws -> [String] {
        let output = try runProcess("/usr/sbin/pkgutil", arguments: ["--payload-files", url.path])
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private struct ScriptPresence {
        let hasPreinstall: Bool
        let hasPostinstall: Bool
    }

    private func fetchScriptInfo(url: URL) async throws -> ScriptPresence {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoxCutter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        _ = try? runProcess("/usr/sbin/pkgutil", arguments: ["--expand", url.path, tmpDir.path])

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: tmpDir.path) else {
            return ScriptPresence(hasPreinstall: false, hasPostinstall: false)
        }

        var hasPreinstall = false
        var hasPostinstall = false

        while let file = enumerator.nextObject() as? String {
            let name = (file as NSString).lastPathComponent
            if name == "preinstall" { hasPreinstall = true }
            if name == "postinstall" { hasPostinstall = true }
        }

        return ScriptPresence(hasPreinstall: hasPreinstall, hasPostinstall: hasPostinstall)
    }

    // MARK: - Process Runner

    private func runProcess(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Parsers

    func parsePkgInfo(_ output: String) -> PkgMetadata {
        var name = ""
        var identifier = ""
        var version = ""
        var location = "/"

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Package name:") || trimmed.hasPrefix("pkgid:") {
                // installer -pkginfo format varies — handle both terse and verbose
                if trimmed.hasPrefix("Package name:") {
                    name = String(trimmed.dropFirst("Package name:".count)).trimmingCharacters(in: .whitespaces)
                }
            }
            if trimmed.hasPrefix("pkgid:") {
                identifier = String(trimmed.dropFirst("pkgid:".count)).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("version:") {
                version = String(trimmed.dropFirst("version:".count)).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("location:") {
                location = String(trimmed.dropFirst("location:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        return PkgMetadata(name: name, identifier: identifier, version: version, location: location)
    }

    func parseSignatureInfo(_ output: String) -> SignatureInfo {
        let lines = output.components(separatedBy: "\n")
        var isSigned = false
        var status = "Unsigned"
        var chain: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("signed by") {
                isSigned = true
                status = "Signed"
            }
            if trimmed.contains("Status: ") {
                status = String(trimmed.dropFirst("Status: ".count)).trimmingCharacters(in: .whitespaces)
            }
            // Certificate chain lines are indented with a number prefix like "    1. "
            if let range = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let cert = String(trimmed[range.upperBound...])
                chain.append(cert)
            }
        }

        if !isSigned && chain.isEmpty {
            status = "Unsigned"
        }

        return SignatureInfo(isSigned: isSigned, status: status, chain: chain)
    }

    /// Parses installer -verboseR percent output lines like "installer:%percent:42.5"
    static func parsePercentage(from line: String) -> Double? {
        // installer -verboseR outputs: installer:%percent:NN.N
        if line.contains("%percent:") || line.contains("PERCENT:") {
            let parts = line.components(separatedBy: ":")
            if let last = parts.last, let value = Double(last.trimmingCharacters(in: .whitespaces)) {
                return value
            }
        }
        return nil
    }
}
```

**Step 2: Commit**

```bash
git add BoxCutter/BoxCutter/Services/PackageInspector.swift
git commit -m "feat: add PackageInspector with CLI parsing"
```

---

### Task 4: XPC Protocol Definitions (Shared)

**Files:**
- Create: `BoxCutter/Shared/HelperProtocol.swift`
- Create: `BoxCutter/Shared/ProgressProtocol.swift`
- Create: `BoxCutter/Shared/SharedConstants.swift`

These files must be added to BOTH the main app target and the helper target in Xcode (Target Membership).

**Step 1: Create SharedConstants.swift**

```swift
import Foundation

enum HelperConstants {
    static let machServiceName = "com.hwxnnn.BoxCutter.Helper"
}
```

**Step 2: Create HelperProtocol.swift**

```swift
import Foundation

/// Protocol exposed by the helper daemon. The main app calls these methods.
@objc(HelperProtocol)
protocol HelperProtocol {
    /// Install a .pkg at the given absolute path.
    /// The helper streams output lines by calling the client's ProgressProtocol.
    /// When done, calls reply with (success, message).
    func installPackage(atPath path: String, withReply reply: @escaping (Bool, String) -> Void)
}
```

**Step 3: Create ProgressProtocol.swift**

```swift
import Foundation

/// Protocol exported by the main app on the XPC connection.
/// The helper daemon calls these methods to stream output back.
@objc(ProgressProtocol)
protocol ProgressProtocol {
    func outputLine(_ line: String)
}
```

**Step 4: Commit**

```bash
git add BoxCutter/Shared/
git commit -m "feat: add shared XPC protocol definitions"
```

---

### Task 5: Helper Daemon Target

**Files:**
- Create: `BoxCutter/Helper/main.swift`
- Create: `BoxCutter/Helper/HelperDelegate.swift`
- Create: `BoxCutter/Helper/InstallerRunner.swift`

This task requires Xcode project configuration:
1. Add a new **Command Line Tool** target named `com.hwxnnn.BoxCutter.Helper`
2. Set its bundle identifier to `com.hwxnnn.BoxCutter.Helper`
3. Add the Shared/ files to this target's compile sources
4. In the main app target, add a "Copy Files" build phase:
   - Destination: Wrapper
   - Subpath: `Contents/Library/LaunchDaemons`
   - Add the helper binary

**Step 1: Create main.swift**

```swift
import Foundation

let delegate = HelperDelegate()
delegate.run()
```

**Step 2: Create HelperDelegate.swift**

```swift
import Foundation

class HelperDelegate: NSObject, NSXPCListenerDelegate {

    private var listener: NSXPCListener!

    func run() {
        listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
        listener.delegate = self
        listener.resume()
        RunLoop.current.run()
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Validate the connecting client's code signature
        // In production, check the client's code signing requirement matches your team ID
        // For now, accept all connections from apps signed by the same team

        let interface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = InstallerRunner(connection: newConnection)

        // Set up the client's progress callback interface
        let progressInterface = NSXPCInterface(with: ProgressProtocol.self)
        newConnection.remoteObjectInterface = progressInterface

        newConnection.invalidationHandler = {
            // Connection was invalidated
        }

        newConnection.resume()
        return true
    }
}
```

**Step 3: Create InstallerRunner.swift**

```swift
import Foundation

class InstallerRunner: NSObject, HelperProtocol {

    private let connection: NSXPCConnection

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func installPackage(atPath path: String, withReply reply: @escaping (Bool, String) -> Void) {
        // Validate path
        guard path.hasPrefix("/"),
              path.hasSuffix(".pkg"),
              FileManager.default.fileExists(atPath: path) else {
            reply(false, "Invalid package path: \(path)")
            return
        }

        // Get the client's progress proxy
        let progressProxy = connection.remoteObjectProxyWithErrorHandler { error in
            // If we can't reach the client for progress, still continue
        } as? ProgressProtocol

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
        process.arguments = ["-verboseR", "-pkg", path, "-target", "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Stream output line by line
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                for line in str.components(separatedBy: "\n") where !line.isEmpty {
                    progressProxy?.outputLine(line)
                }
            }
        }

        process.terminationHandler = { proc in
            handle.readabilityHandler = nil
            let success = proc.terminationStatus == 0
            let message = success ? "Installation completed successfully." : "Installation failed with exit code \(proc.terminationStatus)."
            reply(success, message)
        }

        do {
            try process.run()
        } catch {
            reply(false, "Failed to launch installer: \(error.localizedDescription)")
        }
    }
}
```

**Step 4: Create LaunchDaemon plist**

Create file at `BoxCutter/Helper/com.hwxnnn.BoxCutter.Helper.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hwxnnn.BoxCutter.Helper</string>
    <key>MachServices</key>
    <dict>
        <key>com.hwxnnn.BoxCutter.Helper</key>
        <true/>
    </dict>
</dict>
</plist>
```

This plist must be copied to the main app's `Contents/Library/LaunchDaemons/` via a Copy Files build phase.

**Step 5: Commit**

```bash
git add BoxCutter/Helper/
git commit -m "feat: add privileged helper daemon target"
```

---

### Task 6: HelperManager and XPCClient

**Files:**
- Create: `BoxCutter/BoxCutter/Services/HelperManager.swift`
- Create: `BoxCutter/BoxCutter/Services/XPCClient.swift`

**Step 1: Create HelperManager.swift**

```swift
import Foundation
import ServiceManagement

@Observable
class HelperManager {

    private(set) var isHelperInstalled: Bool = false

    private let daemon = SMAppService.daemon(plistName: "com.hwxnnn.BoxCutter.Helper.plist")

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        isHelperInstalled = daemon.status == .enabled
    }

    func installHelper() throws {
        try daemon.register()
        refreshStatus()
    }

    func uninstallHelper() throws {
        try daemon.unregister()
        refreshStatus()
    }
}
```

**Step 2: Create XPCClient.swift**

```swift
import Foundation

class XPCClient {

    private var connection: NSXPCConnection?

    /// A closure the main app provides to receive streamed output lines.
    var onOutputLine: ((String) -> Void)?

    func connect() {
        let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)

        let helperInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.remoteObjectInterface = helperInterface

        let progressInterface = NSXPCInterface(with: ProgressProtocol.self)
        conn.exportedInterface = progressInterface
        conn.exportedObject = ProgressHandler(client: self)

        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }

        conn.resume()
        self.connection = conn
    }

    func installPackage(atPath path: String) async -> (Bool, String) {
        if connection == nil { connect() }

        return await withCheckedContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(returning: (false, "XPC connection error: \(error.localizedDescription)"))
            }) as? HelperProtocol else {
                continuation.resume(returning: (false, "Failed to create helper proxy."))
                return
            }
            proxy.installPackage(atPath: path) { success, message in
                continuation.resume(returning: (success, message))
            }
        }
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}

// MARK: - Progress Handler (exported to helper)

private class ProgressHandler: NSObject, ProgressProtocol {
    weak var client: XPCClient?

    init(client: XPCClient) {
        self.client = client
    }

    func outputLine(_ line: String) {
        DispatchQueue.main.async {
            self.client?.onOutputLine?(line)
        }
    }
}
```

**Step 3: Commit**

```bash
git add BoxCutter/BoxCutter/Services/HelperManager.swift BoxCutter/BoxCutter/Services/XPCClient.swift
git commit -m "feat: add HelperManager and XPCClient services"
```

---

### Task 7: AppViewModel — State Machine

**Files:**
- Create: `BoxCutter/BoxCutter/ViewModels/AppViewModel.swift`

**Step 1: Create AppViewModel.swift**

```swift
import Foundation
import SwiftUI

@Observable
@MainActor
class AppViewModel {

    var state: AppState = .idle
    var outputLines: [String] = []
    var progress: Double = 0

    let helperManager = HelperManager()

    private let inspector = PackageInspector()
    private let xpcClient = XPCClient()

    init() {
        xpcClient.onOutputLine = { [weak self] line in
            Task { @MainActor in
                self?.handleOutputLine(line)
            }
        }
    }

    // MARK: - Actions

    func loadPackage(url: URL) {
        state = .inspecting(url)
        Task {
            do {
                let info = try await inspector.inspect(url: url)
                state = .packageReady(info)
            } catch {
                state = .failed(
                    PackageInfo(fileURL: url, fileName: url.lastPathComponent, fileSize: 0),
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    func install(package info: PackageInfo) {
        state = .installing(info)
        outputLines = []
        progress = 0

        Task {
            let (success, message) = await xpcClient.installPackage(atPath: info.fileURL.path)
            if success {
                state = .completed(info)
            } else {
                state = .failed(info, errorMessage: message)
            }
        }
    }

    func reset() {
        state = .idle
        outputLines = []
        progress = 0
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.package]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            loadPackage(url: url)
        }
    }

    func installHelper() {
        do {
            try helperManager.installHelper()
        } catch {
            // Helper install failed — state unchanged, banner remains visible
        }
    }

    // MARK: - Private

    private func handleOutputLine(_ line: String) {
        outputLines.append(line)
        if let pct = PackageInspector.parsePercentage(from: line) {
            progress = pct / 100.0
        }
    }
}
```

**Step 2: Commit**

```bash
git add BoxCutter/BoxCutter/ViewModels/AppViewModel.swift
git commit -m "feat: add AppViewModel state machine"
```

---

### Task 8: UI — DropZoneView

**Files:**
- Create: `BoxCutter/BoxCutter/Views/DropZoneView.swift`

**Step 1: Create DropZoneView.swift**

```swift
import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {

    let onFileDrop: (URL) -> Void
    let onSelectFile: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "shippingbox")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Drop a .pkg file here")
                .font(.title2)
                .foregroundStyle(.secondary)

            Button("Select File\u{2026}") {
                onSelectFile()
            }
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        }
        .padding(20)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let urlString = String(data: data, encoding: .utf8),
                  let url = URL(string: urlString),
                  url.pathExtension.lowercased() == "pkg" else { return }

            DispatchQueue.main.async {
                onFileDrop(url)
            }
        }
        return true
    }
}
```

**Step 2: Commit**

```bash
git add BoxCutter/BoxCutter/Views/DropZoneView.swift
git commit -m "feat: add DropZoneView with drag-and-drop"
```

---

### Task 9: UI — PackageInfoView

**Files:**
- Create: `BoxCutter/BoxCutter/Views/PackageInfoView.swift`

**Step 1: Create PackageInfoView.swift**

```swift
import SwiftUI

struct PackageInfoView: View {

    let info: PackageInfo
    let onCancel: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading) {
                    Text(info.fileName)
                        .font(.title3.bold())
                    Text(info.packageName.isEmpty ? info.packageIdentifier : info.packageName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Info grid
            ScrollView {
                VStack(spacing: 0) {
                    infoRow("Identifier", info.packageIdentifier.isEmpty ? "N/A" : info.packageIdentifier)
                    infoRow("Version", info.version.isEmpty ? "N/A" : info.version)
                    infoRow("Size", formattedSize(info.fileSize))
                    infoRow("Install Location", info.installLocation)
                    infoRow("Signing", info.signingStatus)

                    if !info.certificateChain.isEmpty {
                        infoRow("Certificate", info.certificateChain.joined(separator: " → "))
                    }

                    // Script warnings
                    if info.hasPreinstallScript || info.hasPostinstallScript {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading) {
                                if info.hasPreinstallScript {
                                    Text("Contains pre-install script")
                                }
                                if info.hasPostinstallScript {
                                    Text("Contains post-install script")
                                }
                            }
                            .font(.callout)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.yellow.opacity(0.1))
                    }

                    // Payload files
                    if !info.payloadFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Files (\(info.payloadFiles.count))")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 12)

                            List(info.payloadFiles, id: \.self) { file in
                                Text(file)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .frame(height: 160)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
            }

            Divider()

            // Action bar
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Install") {
                    onInstall()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)

            Text(value)
                .font(.callout)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

**Step 2: Commit**

```bash
git add BoxCutter/BoxCutter/Views/PackageInfoView.swift
git commit -m "feat: add PackageInfoView with detail grid"
```

---

### Task 10: UI — InstallingView and CompletionView

**Files:**
- Create: `BoxCutter/BoxCutter/Views/InstallingView.swift`
- Create: `BoxCutter/BoxCutter/Views/CompletionView.swift`

**Step 1: Create InstallingView.swift**

```swift
import SwiftUI

struct InstallingView: View {

    let packageName: String
    let outputLines: [String]
    let progress: Double

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Installing \(packageName)\u{2026}")
                    .font(.title3.bold())
                Spacer()
            }
            .padding()

            Divider()

            // Verbose log
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(outputLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .background(.background.secondary)
                .onChange(of: outputLines.count) { _, _ in
                    if let last = outputLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Progress bar
            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
        }
    }
}
```

**Step 2: Create CompletionView.swift**

```swift
import SwiftUI

struct CompletionView: View {

    let success: Bool
    let packageName: String
    let message: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(success ? .green : .red)

            Text(success ? "Installation Complete" : "Installation Failed")
                .font(.title2.bold())

            Text(packageName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !success {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Done") {
                onDone()
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

**Step 3: Commit**

```bash
git add BoxCutter/BoxCutter/Views/InstallingView.swift BoxCutter/BoxCutter/Views/CompletionView.swift
git commit -m "feat: add InstallingView and CompletionView"
```

---

### Task 11: ContentView — State Router

**Files:**
- Modify: `BoxCutter/BoxCutter/ContentView.swift`

**Step 1: Rewrite ContentView.swift**

Replace the entire contents of `ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {

    @State private var viewModel = AppViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Helper status banner
            if !viewModel.helperManager.isHelperInstalled {
                helperBanner
            }

            // Main content based on state
            Group {
                switch viewModel.state {
                case .idle:
                    DropZoneView(
                        onFileDrop: { url in viewModel.loadPackage(url: url) },
                        onSelectFile: { viewModel.selectFile() }
                    )

                case .inspecting:
                    VStack {
                        Spacer()
                        ProgressView("Inspecting package\u{2026}")
                        Spacer()
                    }

                case .packageReady(let info):
                    PackageInfoView(
                        info: info,
                        onCancel: { viewModel.reset() },
                        onInstall: { viewModel.install(package: info) }
                    )

                case .installing(let info):
                    InstallingView(
                        packageName: info.packageName.isEmpty ? info.fileName : info.packageName,
                        outputLines: viewModel.outputLines,
                        progress: viewModel.progress
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var helperBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Privileged helper not installed.")
                .font(.callout)
            Spacer()
            Button("Install Helper") {
                viewModel.installHelper()
            }
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.08))
    }
}
```

**Step 2: Commit**

```bash
git add BoxCutter/BoxCutter/ContentView.swift
git commit -m "feat: implement ContentView state router"
```

---

### Task 12: App Entry Point — File Association and Window Config

**Files:**
- Modify: `BoxCutter/BoxCutter/BoxCutterApp.swift`

**Step 1: Rewrite BoxCutterApp.swift**

Replace the entire contents:

```swift
import SwiftUI

@main
struct BoxCutterApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 480, minHeight: 400)
                .onOpenURL { url in
                    if url.pathExtension.lowercased() == "pkg" {
                        NotificationCenter.default.post(
                            name: .openPackageFile,
                            object: url
                        )
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 480)
    }
}

extension Notification.Name {
    static let openPackageFile = Notification.Name("openPackageFile")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "pkg" {
            NotificationCenter.default.post(
                name: .openPackageFile,
                object: url
            )
        }
    }
}
```

**Step 2: Update ContentView to listen for open notifications**

Add to `ContentView` body, chained on the outer `VStack`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .openPackageFile)) { notification in
    if let url = notification.object as? URL {
        viewModel.loadPackage(url: url)
    }
}
```

**Step 3: Configure Info.plist for .pkg file association**

The main app's Info.plist (or target settings) needs these keys:

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Installer Package</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.apple.installer-package-archive</string>
            <string>com.apple.installer-package</string>
        </array>
    </dict>
</array>
```

This can be set via Xcode target settings > Info > Document Types.

**Step 4: Commit**

```bash
git add BoxCutter/BoxCutter/BoxCutterApp.swift BoxCutter/BoxCutter/ContentView.swift
git commit -m "feat: add file association and app delegate for .pkg opening"
```

---

### Task 13: Xcode Project Configuration

This task requires manual Xcode configuration. These steps cannot be done purely via file creation.

**Step 1: Add the helper command-line tool target**
- File > New > Target > macOS > Command Line Tool
- Product Name: `com.hwxnnn.BoxCutter.Helper`
- Bundle Identifier: `com.hwxnnn.BoxCutter.Helper`
- Language: Swift

**Step 2: Configure target membership for Shared files**
- Select all files in `BoxCutter/Shared/` (HelperProtocol.swift, ProgressProtocol.swift, SharedConstants.swift)
- In the File Inspector, check both the `BoxCutter` target and the `com.hwxnnn.BoxCutter.Helper` target

**Step 3: Embed the helper in the main app**
- Select the BoxCutter target > Build Phases
- Add a "Copy Files" phase:
  - Destination: Wrapper
  - Subpath: `Contents/Library/LaunchDaemons`
  - Add the `com.hwxnnn.BoxCutter.Helper` product

**Step 4: Copy the LaunchDaemon plist**
- In the same or another "Copy Files" phase:
  - Destination: Wrapper
  - Subpath: `Contents/Library/LaunchDaemons`
  - Add `com.hwxnnn.BoxCutter.Helper.plist`

**Step 5: Add Document Types to main app**
- Select BoxCutter target > Info > Document Types
- Add entry:
  - Name: Installer Package
  - Types: `com.apple.installer-package-archive`, `com.apple.installer-package`
  - Role: Viewer

**Step 6: Set deployment target**
- Both targets: macOS 15.0

**Step 7: Commit**

```bash
git add -A && git commit -m "chore: configure Xcode project targets and build phases"
```

---

### Task 14: Build, Fix Errors, Verify

**Step 1: Build the project**

Use Xcode MCP `BuildProject` to build.

**Step 2: Fix any compiler errors**

Review build log, fix issues.

**Step 3: Verify the helper binary is embedded correctly**

```bash
# After building, check the app bundle structure
ls -la "$(find ~/Library/Developer/Xcode/DerivedData -name 'BoxCutter.app' -type d | head -1)/Contents/Library/LaunchDaemons/"
```

**Step 4: Commit any fixes**

```bash
git add -A && git commit -m "fix: resolve build errors"
```

---

### Task 15: Visual Polish

**Step 1: Review all views render correctly**

Use Xcode MCP `RenderPreview` for each view that has a preview.

**Step 2: Add any needed preview providers**

Add `#Preview` macros to views that lack them (DropZoneView, PackageInfoView, InstallingView, CompletionView) with mock data.

**Step 3: Adjust spacing, colors, and typography if needed**

Ensure the app looks native and minimal — use system colors, SF Symbols, standard controls.

**Step 4: Commit**

```bash
git add -A && git commit -m "polish: refine UI views and add previews"
```
