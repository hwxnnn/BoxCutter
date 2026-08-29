import Foundation
import AppKit
import Security

enum DMGError: LocalizedError {
    case mountFailed(String)
    case copyFailed(String)
    case unmountFailed(String)

    var errorDescription: String? {
        switch self {
        case .mountFailed(let msg): "Failed to mount DMG: \(msg)"
        case .copyFailed(let msg): "Failed to copy app: \(msg)"
        case .unmountFailed(let msg): "Failed to unmount DMG: \(msg)"
        }
    }
}

// nonisolated on every method: SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor would otherwise
// default all static funcs to @MainActor, causing waitUntilExit / directory enumeration
// to run on the main thread and produce beachballs.
enum DMGService {

    /// hdiutil reports these while a previous attachment of the same image is still
    /// being torn down. They clear on their own within about a second.
    private static let transientAttachErrors = [
        "resource busy",
        "resource temporarily unavailable"
    ]

    // MARK: - Mount / Unmount

    /// Mounts the image. `browsable: false` (the default) hides the volume from Finder
    /// for the install flow; `true` mounts it the way macOS would on a double-click.
    nonisolated static func mount(url: URL, browsable: Bool = false) async throws -> URL {
        var arguments = ["attach", url.path, "-plist"]
        if !browsable {
            arguments.insert("-nobrowse", at: 2)
        }

        let result = await runProcess("/usr/bin/hdiutil", arguments: arguments)

        if result.status != 0 {
            // Attaching an image that is still attached fails with "Resource busy".
            // `unmount` is fire-and-forget, so a previous detach may not have finished
            // (or may have failed) — reuse the mount we already have instead of
            // refusing the drop.
            if let existing = await attachedMountPoint(for: url) {
                return existing
            }
            // A detach still tearing down leaves nothing for attachedMountPoint to find
            // and reports one of these, so back off briefly and try again.
            let message = sanitized(result.standardError)
            if Self.transientAttachErrors.contains(where: { message.localizedCaseInsensitiveContains($0) }) {
                for delay in [400, 900] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    let retry = await runProcess("/usr/bin/hdiutil", arguments: arguments)
                    if retry.status == 0, let mountPoint = parseMountPoint(from: retry.standardOutput) {
                        return URL(fileURLWithPath: mountPoint)
                    }
                    if let existing = await attachedMountPoint(for: url) {
                        return existing
                    }
                }
            }
            throw DMGError.mountFailed(failureMessage(from: result))
        }

        guard let mountPoint = parseMountPoint(from: result.standardOutput) else {
            throw DMGError.mountFailed("Could not determine mount point.")
        }
        return URL(fileURLWithPath: mountPoint)
    }

    /// Mount point of an already-attached copy of this image, if macOS has one.
    nonisolated private static func attachedMountPoint(for url: URL) async -> URL? {
        let result = await runProcess("/usr/bin/hdiutil", arguments: ["info", "-plist"])
        guard result.status == 0,
              let data = result.standardOutput.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return nil
        }

        let target = url.resolvingSymlinksInPath().standardized.path
        for image in images {
            guard let imagePath = image["image-path"] as? String,
                  URL(fileURLWithPath: imagePath).resolvingSymlinksInPath().standardized.path == target,
                  let entities = image["system-entities"] as? [[String: Any]],
                  let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
                continue
            }
            return URL(fileURLWithPath: mountPoint)
        }
        return nil
    }

    /// hdiutil on macOS 26+ prints a deprecation notice about `-nobrowse` to stderr on
    /// every call. It is not an error, but it is the *first* line, so without stripping
    /// it the completion dialog shows the warning and truncates the real reason.
    nonisolated private static func sanitized(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("hdiutil: WARNING:") }
            .joined(separator: "\n")
    }

    nonisolated private static func failureMessage(from result: ProcessResult) -> String {
        let stderr = sanitized(result.standardError)
        if !stderr.isEmpty { return stderr }
        let stdout = sanitized(result.standardOutput)
        return stdout.isEmpty ? "hdiutil could not attach the image." : stdout
    }

    /// Re-attaches an already-mounted image without `-nobrowse` so it appears in Finder.
    /// Returns the new mount point. If the detach fails the volume is still mounted, so
    /// the existing (hidden) mount point is returned rather than leaking a second mount.
    nonisolated static func remountBrowsable(url: URL, currentMountPoint: URL) async throws -> URL {
        let detach = await runProcess(
            "/usr/bin/hdiutil",
            arguments: ["detach", currentMountPoint.path, "-quiet"]
        )
        guard detach.status == 0 else { return currentMountPoint }
        return try await mount(url: url, browsable: true)
    }

    /// Fire-and-forget: does not block the calling thread.
    nonisolated static func unmount(mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-quiet"]
        try? process.run()
        // No waitUntilExit — hdiutil detach runs in the background
    }

    // MARK: - App Discovery

    nonisolated static func findApps(at mountPoint: URL) throws -> [DMGAppEntry] {
        let apps = try scan(mountPoint, extension: "app")
            .compactMap { appEntry(at: $0, mountPoint: mountPoint) }
        return apps.sorted { $0.appSize > $1.appSize }
    }

    nonisolated static func findPackages(at mountPoint: URL) throws -> [DMGPkgEntry] {
        let pkgs = try scan(mountPoint, extension: "pkg")
            .map { pkgEntry(at: $0, mountPoint: mountPoint) }
        return pkgs.sorted {
            $0.pkgName.localizedStandardCompare($1.pkgName) == .orderedAscending
        }
    }

    /// Returns matching entries at the volume root plus one level of subfolders.
    /// Never descends into bundles (.app and some .pkg are directories) and never
    /// follows symlinks — the `Applications` alias shipped in most DMGs points at
    /// /Applications, and walking it would list every installed app as DMG content.
    nonisolated private static func scan(_ root: URL, extension ext: String) throws -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]

        let top = try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var results = top.filter { $0.pathExtension.lowercased() == ext }

        for entry in top where isTraversableDirectory(entry) {
            guard let children = try? fm.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { continue }
            results.append(contentsOf: children.filter { $0.pathExtension.lowercased() == ext })
        }

        return results
    }

    nonisolated private static func isTraversableDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        ) else { return false }
        return values.isDirectory == true
            && values.isSymbolicLink != true
            && values.isPackage != true
    }

    /// Immediate subfolder name inside the volume, empty when the entry sits at the root.
    nonisolated private static func subfolder(of url: URL, mountPoint: URL) -> String {
        let parent = url.deletingLastPathComponent().standardized
        guard parent.path != mountPoint.standardized.path else { return "" }
        return parent.lastPathComponent
    }

    nonisolated private static func pkgEntry(at url: URL, mountPoint: URL) -> DMGPkgEntry {
        // A .pkg can be a flat file or, for older distribution packages, a bundle directory.
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let size: Int64
        if values?.isDirectory == true {
            size = directorySize(at: url)
        } else {
            size = Int64(values?.fileSize ?? 0)
        }

        return DMGPkgEntry(
            pkgURL: url,
            pkgName: url.deletingPathExtension().lastPathComponent,
            fileSize: size,
            subfolder: subfolder(of: url, mountPoint: mountPoint)
        )
    }

    nonisolated private static func appEntry(at url: URL, mountPoint: URL) -> DMGAppEntry? {
        let name = url.deletingPathExtension().lastPathComponent
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        var bundleID = ""
        var version = ""
        if let dict = NSDictionary(contentsOf: plistURL) {
            bundleID = dict["CFBundleIdentifier"] as? String ?? ""
            version = dict["CFBundleShortVersionString"] as? String
                   ?? dict["CFBundleVersion"] as? String
                   ?? ""
        }

        let isSigned = isCodeSignatureValid(at: url)

        let installedURL = URL(fileURLWithPath: "/Applications/\(name).app")
        var installedVersion: String? = nil
        if FileManager.default.fileExists(atPath: installedURL.path),
           let installedDict = NSDictionary(contentsOf: installedURL.appendingPathComponent("Contents/Info.plist")) {
            installedVersion = installedDict["CFBundleShortVersionString"] as? String
                            ?? installedDict["CFBundleVersion"] as? String
        }

        return DMGAppEntry(
            appURL: url,
            appName: name,
            bundleIdentifier: bundleID,
            bundleVersion: version,
            appSize: directorySize(at: url),
            fileCount: fileCount(at: url),
            isCodeSigned: isSigned,
            installedVersion: installedVersion,
            subfolder: subfolder(of: url, mountPoint: mountPoint)
        )
    }

    // MARK: - Copy App to /Applications

    /// Copies an app bundle to /Applications using `ditto`, reporting progress
    /// based on file count. Returns the installed URL on success.
    nonisolated static func copyApp(
        from source: DMGAppEntry,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let destination = URL(fileURLWithPath: "/Applications/\(source.appName).app")
        let temporaryDestination = URL(fileURLWithPath: "/Applications/.BoxCutter-\(UUID().uuidString)-\(source.appName).app")
        let fm = FileManager.default

        try? fm.removeItem(at: temporaryDestination)

        let totalFiles = source.fileCount
        nonisolated(unsafe) var copiedFiles = 0

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-V", source.appURL.path, temporaryDestination.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let str = String(data: data, encoding: .utf8) else { return }
                let lines = str.components(separatedBy: .newlines).filter { !$0.isEmpty }
                copiedFiles += lines.count
                let pct = totalFiles > 0
                    ? min(Double(copiedFiles) / Double(totalFiles), 0.99)
                    : 0
                Task { @MainActor in onProgress(pct) }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    do {
                        let installedURL = try finalizeAppCopy(
                            from: temporaryDestination,
                            to: destination
                        )
                        Task { @MainActor in onProgress(1.0) }
                        continuation.resume(returning: installedURL)
                    } catch {
                        removeAppCopy(at: temporaryDestination)
                        continuation.resume(throwing: error)
                    }
                } else {
                    removeAppCopy(at: temporaryDestination)
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
                removeAppCopy(at: temporaryDestination)
                continuation.resume(throwing: DMGError.copyFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Orphan cleanup

    /// Removes any leftover hidden staging bundles from a prior crashed/killed install.
    /// Backup bundles are intentionally preserved because failed replacement errors may
    /// point the user at them for manual recovery.
    /// Cheap to run at app launch — typically zero entries match.
    nonisolated static func cleanupOrphanedStagingBundles() {
        let fm = FileManager.default
        let applications = URL(fileURLWithPath: "/Applications")
        guard let entries = try? fm.contentsOfDirectory(
            at: applications,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }

        for entry in entries {
            let name = entry.lastPathComponent
            if name.hasPrefix(".BoxCutter-"),
               !name.hasPrefix(".BoxCutter-backup-") {
                try? fm.removeItem(at: entry)
            }
        }
    }

    // MARK: - Quarantine

    /// Removes quarantine and extended attributes so Gatekeeper allows launch.
    nonisolated static func removeQuarantine(at url: URL) async -> Bool {
        return await runProcess("/usr/bin/xattr", arguments: ["-cr", url.path]).status == 0
    }

    // MARK: - Private helpers

    nonisolated private static func directorySize(at url: URL) -> Int64 {
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

    nonisolated private static func fileCount(at url: URL) -> Int {
        let fm = FileManager.default
        // Do NOT skip hidden files — ditto -V counts all files including hidden
        // ones and ._resource-fork files. Skipping them causes progress to stall at 99%.
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        for _ in enumerator { count += 1 }
        return count
    }

    nonisolated private static func isCodeSignatureValid(at url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return false
        }

        // Default flags rather than strict+deep: the latter is stricter than
        // Gatekeeper-at-launch and produces false negatives on legitimately signed
        // apps (Electron bundles, older Sparkle, stray .DS_Store inside the bundle).
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    nonisolated private static func finalizeAppCopy(from temporaryURL: URL, to destinationURL: URL) throws -> URL {
        let fm = FileManager.default
        let backupURL = URL(
            fileURLWithPath: "/Applications/.BoxCutter-backup-\(UUID().uuidString)-\(destinationURL.lastPathComponent)"
        )

        if fm.fileExists(atPath: destinationURL.path) {
            do {
                try fm.moveItem(at: destinationURL, to: backupURL)
            } catch {
                throw DMGError.copyFailed("Failed to move existing app aside: \(error.localizedDescription)")
            }

            do {
                try fm.moveItem(at: temporaryURL, to: destinationURL)
                trashOrRemove(backupURL)
            } catch {
                if !fm.fileExists(atPath: destinationURL.path),
                   (try? fm.moveItem(at: backupURL, to: destinationURL)) != nil {
                    throw DMGError.copyFailed("Failed to replace existing app: \(error.localizedDescription)")
                }
                if fm.fileExists(atPath: backupURL.path) {
                    throw DMGError.copyFailed(
                        "Failed to replace existing app: \(error.localizedDescription). " +
                        "Your previous version was preserved at \(backupURL.path)."
                    )
                }
                throw DMGError.copyFailed("Failed to replace existing app: \(error.localizedDescription)")
            }
        } else {
            do {
                try fm.moveItem(at: temporaryURL, to: destinationURL)
            } catch {
                throw DMGError.copyFailed("Failed to move app into Applications: \(error.localizedDescription)")
            }
        }

        return destinationURL
    }

    nonisolated private static func trashOrRemove(_ url: URL) {
        let fm = FileManager.default
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
        } catch {
            try? fm.removeItem(at: url)
        }
    }

    nonisolated private static func removeAppCopy(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    struct ProcessResult {
        let standardOutput: String
        let standardError: String
        let status: Int32
    }

    /// Collects both streams off the calling thread. Kept separate because hdiutil
    /// writes its plist to stdout and its warnings to stderr; merging them corrupts
    /// the plist parse and lets a warning masquerade as the failure reason.
    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        func append(_ data: Data) {
            lock.lock()
            storage.append(data)
            lock.unlock()
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(data: storage, encoding: .utf8) ?? ""
        }
    }

    nonisolated private static func runProcess(
        _ path: String,
        arguments: [String]
    ) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ProcessResult(
                        standardOutput: "",
                        standardError: error.localizedDescription,
                        status: -1
                    ))
                    return
                }

                // Drain both pipes in parallel. Reading one to completion before the
                // other deadlocks as soon as the second fills its 64K buffer.
                let outBuffer = OutputBuffer()
                let errBuffer = OutputBuffer()
                let group = DispatchGroup()

                let outHandle = outPipe.fileHandleForReading
                let errHandle = errPipe.fileHandleForReading

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    outBuffer.append(outHandle.readDataToEndOfFile())
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errBuffer.append(errHandle.readDataToEndOfFile())
                    group.leave()
                }

                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: ProcessResult(
                    standardOutput: outBuffer.text,
                    standardError: errBuffer.text,
                    status: process.terminationStatus
                ))
            }
        }
    }

    nonisolated private static func parseMountPoint(from plistOutput: String) -> String? {
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
