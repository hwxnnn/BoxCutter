import Foundation

class InstallerRunner: NSObject, HelperProtocol {

    private let connection: NSXPCConnection

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func installPackage(atPath path: String, target: String, withReply reply: @escaping (Bool, String) -> Void) {
        // Canonicalize path to prevent traversal attacks
        let canonicalPath = URL(fileURLWithPath: path).standardized.path
        let canonicalTarget = URL(fileURLWithPath: target).standardized.path

        guard canonicalPath.hasPrefix("/"),
              canonicalPath.hasSuffix(".pkg"),
              !canonicalPath.contains("/../"),
              FileManager.default.fileExists(atPath: canonicalPath),
              canonicalTarget.hasPrefix("/"),
              !canonicalTarget.contains("/../") else {
            reply(false, "Invalid package path or target.")
            return
        }

        let progressProxy = connection.remoteObjectProxyWithErrorHandler { error in
            // If we can't reach the client for progress, still continue
        } as? ProgressProtocol

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
        process.arguments = ["-verboseR", "-pkg", canonicalPath, "-target", canonicalTarget]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

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
