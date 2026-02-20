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
        let count = fileCount(at: url)
        return DMGAppEntry(
            appURL: url,
            appName: name,
            bundleIdentifier: bundleID,
            appSize: size,
            fileCount: count
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
