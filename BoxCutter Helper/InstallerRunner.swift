import Foundation

class InstallerRunner: NSObject, HelperProtocol {

    private let connection: NSXPCConnection

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func ping(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func runDiagnostic(withReply reply: @escaping (Bool, String) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/id")
        process.arguments = ["-u"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { proc in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let uid = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard proc.terminationStatus == 0 else {
                reply(false, "Helper could not run /usr/bin/id (exit code \(proc.terminationStatus)).")
                return
            }
            guard uid == "0" else {
                reply(false, "Helper is running as uid \(uid.isEmpty ? "unknown" : uid), expected 0 (root).")
                return
            }
            reply(true, "Helper is reachable and ran /usr/bin/id as uid 0 (root).")
        }

        do {
            try process.run()
        } catch {
            reply(false, "Helper could not launch a process: \(error.localizedDescription)")
        }
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
