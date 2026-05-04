import Foundation

/// Fallback installer that uses AppleScript privilege escalation.
/// Prompts for admin password each time but works without the helper daemon.
class DirectInstaller {

    var onOutputLine: ((String) -> Void)?

    func installPackage(atPath path: String, target: String = "/") async -> (Bool, String) {
        // Copy pkg to /tmp/ so the privileged process can access it
        // (macOS TCC blocks root from reading ~/Downloads, ~/Desktop, etc.)
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        let sessionID = UUID().uuidString
        let tmpPkg = "/tmp/BoxCutter-\(sessionID)-\(fileName)"
        let logFile = "/tmp/BoxCutter-\(sessionID).log"

        defer {
            try? FileManager.default.removeItem(atPath: tmpPkg)
            try? FileManager.default.removeItem(atPath: logFile)
        }

        do {
            try FileManager.default.copyItem(atPath: path, toPath: tmpPkg)
        } catch {
            return (false, "Failed to prepare package: \(error.localizedDescription)")
        }

        // Create the log file so we can start watching it
        FileManager.default.createFile(atPath: logFile, contents: nil)

        let appleScript = """
        on run argv
            set pkgPath to item 1 of argv
            set targetPath to item 2 of argv
            set logPath to item 3 of argv
            set installerCommand to "/usr/sbin/installer -verboseR -pkg " & quoted form of pkgPath & " -target " & quoted form of targetPath & " > " & quoted form of logPath & " 2>&1"
            do shell script installerCommand with administrator privileges
        end run
        """

        // Start tailing the log file for real-time output
        let tailTask = Task { [weak self] in
            await self?.tailLogFile(atPath: logFile)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript, tmpPkg, target, logFile]

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        let result: (Bool, String) = await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                let success = proc.terminationStatus == 0
                let message: String
                if success {
                    message = "Installation completed successfully."
                } else if !errStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

        tailTask.cancel()

        return result
    }

    private func tailLogFile(atPath path: String) async {
        var offset: UInt64 = 0

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))

            guard let handle = FileHandle(forReadingAtPath: path) else { continue }
            defer { handle.closeFile() }

            handle.seek(toFileOffset: offset)
            let data = handle.readDataToEndOfFile()

            if !data.isEmpty {
                offset += UInt64(data.count)
                if let str = String(data: data, encoding: .utf8) {
                    let lines = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                    for line in lines {
                        await MainActor.run { [weak self] in
                            self?.onOutputLine?(line)
                        }
                    }
                }
            }
        }
    }
}
