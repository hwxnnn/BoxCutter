import Foundation

enum PackageInspector {

    enum InspectionError: LocalizedError {
        case fileNotFound(URL)
        case notAPackage(URL)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url): return "File not found: \(url.path)"
            case .notAPackage(let url): return "Not a .pkg file: \(url.lastPathComponent)"
            }
        }
    }

    // MARK: - Quick Inspection (fast — runs on file drop)

    static func inspectQuick(url: URL) async throws -> PackageInfo {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InspectionError.fileNotFound(url)
        }
        guard url.pathExtension.lowercased() == "pkg" else {
            throw InspectionError.notAPackage(url)
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        var info = PackageInfo(
            fileURL: url,
            fileName: url.lastPathComponent,
            fileSize: fileSize
        )

        // Run pkginfo and signature check in TRUE parallel (detached from actor)
        async let pkgInfo = Task.detached { try? Self.fetchPackageInfo(url: url) }.value
        async let sigInfo = Task.detached { try? Self.fetchSignatureInfo(url: url) }.value

        let (pkg, sig) = await (pkgInfo, sigInfo)

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

        return info
    }

    // MARK: - Detail Inspection (lazy — runs on "Details" tap)

    static func inspectDetails(info: inout PackageInfo) async {
        let url = info.fileURL

        async let files = Task.detached { try? Self.fetchPayloadFiles(url: url) }.value
        async let scripts = Task.detached { try? Self.fetchScriptInfo(url: url) }.value

        let (payloadFiles, scriptInfo) = await (files, scripts)

        if let payloadFiles {
            info.payloadFiles = payloadFiles
        }
        if let scriptInfo {
            info.hasPreinstallScript = scriptInfo.hasPreinstall
            info.hasPostinstallScript = scriptInfo.hasPostinstall
        }
        info.detailsLoaded = true
    }

    // MARK: - CLI Wrappers

    private struct PkgMetadata {
        let name: String
        let identifier: String
        let version: String
        let location: String
    }

    private static func fetchPackageInfo(url: URL) throws -> PkgMetadata {
        let output = try runProcess("/usr/sbin/installer", arguments: ["-pkginfo", "-pkg", url.path])
        return parsePkgInfo(output)
    }

    private struct SignatureInfo {
        let isSigned: Bool
        let status: String
        let chain: [String]
    }

    private static func fetchSignatureInfo(url: URL) throws -> SignatureInfo {
        let output = try runProcess("/usr/sbin/pkgutil", arguments: ["--check-signature", url.path])
        return parseSignatureInfo(output)
    }

    private static func fetchPayloadFiles(url: URL) throws -> [String] {
        let output = try runProcess("/usr/sbin/pkgutil", arguments: ["--payload-files", url.path])
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private struct ScriptPresence {
        let hasPreinstall: Bool
        let hasPostinstall: Bool
    }

    private static func fetchScriptInfo(url: URL) throws -> ScriptPresence {
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

    private static func runProcess(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Parsers

    private static func parsePkgInfo(_ output: String) -> PkgMetadata {
        var name = ""
        var identifier = ""
        var version = ""
        var location = "/"

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Package name:") {
                name = String(trimmed.dropFirst("Package name:".count)).trimmingCharacters(in: .whitespaces)
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

    private static func parseSignatureInfo(_ output: String) -> SignatureInfo {
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
}
