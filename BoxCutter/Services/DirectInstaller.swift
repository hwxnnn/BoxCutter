import Foundation

/// Fallback installer that uses AppleScript privilege escalation.
/// Prompts for admin password each time but works without the helper daemon.
class DirectInstaller {

    var onOutputLine: ((String) -> Void)?

    func installPackage(atPath path: String) async -> (Bool, String) {
        // Copy pkg to /tmp/ so the privileged process can access it
        // (macOS TCC blocks root from reading ~/Downloads, ~/Desktop, etc.)
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        let tmpPath = "/tmp/BoxCutter-\(UUID().uuidString)-\(fileName)"
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        do {
            try FileManager.default.copyItem(atPath: path, toPath: tmpPath)
        } catch {
            return (false, "Failed to prepare package: \(error.localizedDescription)")
        }

        let escaped = tmpPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = "do shell script \"/usr/sbin/installer -verboseR -pkg \\\"\(escaped)\\\" -target /\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return await withCheckedContinuation { continuation in
            let handle = stdoutPipe.fileHandleForReading

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

            process.terminationHandler = { [weak self] proc in
                handle.readabilityHandler = nil

                // Read remaining stdout
                let remaining = handle.readDataToEndOfFile()
                if !remaining.isEmpty, let str = String(data: remaining, encoding: .utf8) {
                    for line in str.components(separatedBy: "\n") where !line.isEmpty {
                        DispatchQueue.main.async {
                            self?.onOutputLine?(line)
                        }
                    }
                }

                // Read stderr for error details
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                let success = proc.terminationStatus == 0
                let message: String
                if success {
                    message = "Installation completed successfully."
                } else if !errStr.isEmpty {
                    message = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    message = "Installation failed with exit code \(proc.terminationStatus)."
                }
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
