import Foundation

/// Fallback installer that uses AppleScript privilege escalation.
/// Prompts for admin password each time but works without the helper daemon.
class DirectInstaller {

    var onOutputLine: ((String) -> Void)?

    func installPackage(atPath path: String) async -> (Bool, String) {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = "/usr/sbin/installer -verboseR -pkg '\(escaped)' -target / 2>&1"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"\(script)\" with administrator privileges"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return await withCheckedContinuation { continuation in
            let handle = pipe.fileHandleForReading

            // osascript returns all output at once when the command finishes,
            // but readabilityHandler will fire as data becomes available
            handle.readabilityHandler = { [weak self] fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    for line in str.components(separatedBy: "\n") where !line.isEmpty {
                        DispatchQueue.main.async {
                            self?.onOutputLine?(line)
                        }
                    }
                }
            }

            process.terminationHandler = { proc in
                handle.readabilityHandler = nil
                // Read any remaining data
                let remaining = handle.readDataToEndOfFile()
                if !remaining.isEmpty, let str = String(data: remaining, encoding: .utf8) {
                    for line in str.components(separatedBy: "\n") where !line.isEmpty {
                        DispatchQueue.main.async { [weak self] in
                            self?.onOutputLine?(line)
                        }
                    }
                }

                let success = proc.terminationStatus == 0
                let message = success
                    ? "Installation completed successfully."
                    : "Installation failed with exit code \(proc.terminationStatus)."
                continuation.resume(returning: (success, message))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: (false, "Failed to launch installer: \(error.localizedDescription)"))
            }
        }
    }
}
