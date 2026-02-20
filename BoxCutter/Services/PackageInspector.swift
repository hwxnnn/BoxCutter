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

    private func parsePkgInfo(_ output: String) -> PkgMetadata {
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

    private func parseSignatureInfo(_ output: String) -> SignatureInfo {
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

    /// Parses installer -verboseR percent output lines like "installer:%percent:42.5"
    static func parsePercentage(from line: String) -> Double? {
        if line.contains("%percent:") || line.contains("PERCENT:") {
            let parts = line.components(separatedBy: ":")
            if let last = parts.last, let value = Double(last.trimmingCharacters(in: .whitespaces)) {
                return value
            }
        }
        return nil
    }
}
