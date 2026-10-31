import Foundation
import CryptoKit

/// Standalone integration checks using the production DMG scanner and copy pipeline.
/// Pass the Impactor DMG path; all installed copies go to a disposable temp directory.
@main
struct DMGThinningTests {
    enum Failure: Error { case check(String) }

    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.check(message) }
        print("PASS: \(message)")
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.check("\(executable) failed with \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func architectures(_ bundle: URL) throws -> Set<String> {
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
            format: nil
        ) as! [String: Any]
        let executable = bundle.appendingPathComponent("Contents/MacOS/\(plist["CFBundleExecutable"] as! String)")
        return Set(try run("/usr/bin/lipo", ["-archs", executable.path]).split(separator: " ").map(String.init))
    }

    static func byteCount(_ bundle: URL) throws -> Int64 {
        let files = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])!
        var size: Int64 = 0
        for case let url as URL in files {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true { size += Int64(values.fileSize ?? 0) }
        }
        return size
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw Failure.check("Usage: DMGThinningTests /path/to/Impactor-macos-universal.dmg")
        }
        let fm = FileManager.default
        let image = URL(fileURLWithPath: CommandLine.arguments[1])
        let imageHash = SHA256.hash(data: try Data(contentsOf: image, options: .mappedIfSafe))
        let mount = try await DMGService.mount(url: image)
        defer { DMGService.unmount(mountPoint: mount) }
        let apps = try DMGService.findApps(at: mount)
        try check(apps.count == 1 && apps[0].appName == "Impactor", "find Impactor in the real DMG without following its Applications alias")
        let source = apps[0]
        try check(source.thinningArchitecture == BinaryArchitecture.native, "detect universal executable and choose native hardware architecture")
        try check(source.isCodeSigned, "recognize the original code signature")
        let info = DMGInfo(dmgURL: image, dmgFileName: image.lastPathComponent, mountPoint: mount,
                           apps: apps, pkgs: [], selectedAppIDs: [source.appURL], selectedPkgIDs: [])
        try check(info.appIDsToThin.isEmpty, "architecture removal is opt-in")

        let root = fm.temporaryDirectory.appendingPathComponent("BoxCutter-thinning-test-\(UUID().uuidString)")
        print("Test copies: \(root.path)")
        func directory(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let full = try await DMGService.copyApp(from: source, applicationsDirectory: directory("full")) { _ in }
        try check(architectures(full) == ["arm64", "x86_64"], "normal install keeps both architectures")
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", full.path])

        let thin = try await DMGService.copyApp(from: source, stripUnusedArchitecture: true,
                                               applicationsDirectory: directory("thin")) { _ in }
        try check(architectures(thin) == [BinaryArchitecture.native.rawValue], "opted-in install keeps only the native architecture")
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", thin.path])
        try check(true, "thinned app and nested code retain valid original signatures")
        let fullSize = try byteCount(full)
        let thinSize = try byteCount(thin)
        try check(thinSize < fullSize, "save \(fullSize - thinSize) bytes (\(fullSize) → \(thinSize))")
        try check(source.estimatedBytesSaved == fullSize - thinSize, "first-use savings estimate matches actual Impactor reduction")
        try check(fm.contents(atPath: full.appendingPathComponent("Contents/Info.plist").path)
                  == fm.contents(atPath: thin.appendingPathComponent("Contents/Info.plist").path), "preserve bundle metadata")

        let thinEntry = try DMGService.findApps(at: thin.deletingLastPathComponent())[0]
        try check(thinEntry.thinningArchitecture == nil, "single-architecture apps do not offer removal")
        do {
            _ = try await DMGService.copyApp(from: thinEntry, stripUnusedArchitecture: true,
                                             applicationsDirectory: directory("unsupported")) { _ in }
            throw Failure.check("Unsupported architecture request was accepted")
        } catch DMGError.copyFailed {
            try check(true, "reject unsupported thinning requests")
        }

        // Simulate a file being changed between inspection and installation. The signed
        // status comes from inspection, so the staged copy must be validated again.
        let badParent = try directory("changed-source")
        let badApp = badParent.appendingPathComponent("Impactor.app")
        _ = try run("/usr/bin/ditto", [source.appURL.path, badApp.path])
        let executable = badApp.appendingPathComponent("Contents/MacOS/Impactor")
        var data = try Data(contentsOf: executable)
        // Alter executable bytes in both slices, without changing the Mach-O headers.
        for arch in ["arm64", "x86_64"] {
            let slice = badParent.appendingPathComponent(arch)
            _ = try run("/usr/bin/lipo", [executable.path, "-thin", arch, "-output", slice.path])
            let sliceData = try Data(contentsOf: slice)
            if let range = data.range(of: sliceData) { data[range.lowerBound + 4096] ^= 1 }
        }
        try data.write(to: executable)
        let changed = DMGAppEntry(appURL: badApp, appName: source.appName,
                                  bundleIdentifier: source.bundleIdentifier, bundleVersion: source.bundleVersion,
                                  appSize: source.appSize, fileCount: source.fileCount, isCodeSigned: true,
                                  installedVersion: nil, subfolder: "", thinningArchitecture: source.thinningArchitecture)
        do {
            _ = try await DMGService.copyApp(from: changed, stripUnusedArchitecture: true,
                                             applicationsDirectory: full.deletingLastPathComponent()) { _ in }
            throw Failure.check("Damaged signed app was accepted")
        } catch DMGError.copyFailed {
            try check(architectures(full) == ["arm64", "x86_64"], "signature failure leaves the existing app untouched")
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", full.path])
            let entries = try fm.contentsOfDirectory(atPath: full.deletingLastPathComponent().path)
            try check(entries == ["Impactor.app"], "failed copy cleans staging without creating recovery backups")
        }
        try check(SHA256.hash(data: Data(contentsOf: image, options: .mappedIfSafe)) == imageHash, "original DMG is unchanged")
    }
}
