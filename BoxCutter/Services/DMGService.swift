import Foundation
import AppKit
import Security

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

// nonisolated on every method: SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor would otherwise
// default all static funcs to @MainActor, causing waitUntilExit / directory enumeration
// to run on the main thread and produce beachballs.
enum DMGService {

    // MARK: - Mount / Unmount

    nonisolated static func mount(url: URL) async throws -> URL {
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

    nonisolated private static func appEntry(at url: URL) -> DMGAppEntry? {
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
            installedVersion: installedVersion
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
        let (_, status) = await runProcess("/usr/bin/xattr", arguments: ["-cr", url.path])
        return status == 0
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

    /// Non-blocking process runner using terminationHandler instead of waitUntilExit.
    nonisolated private static func runProcess(
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
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, proc.terminationStatus))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (error.localizedDescription, -1))
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
