import Foundation
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
class AppViewModel {

    var state: AppState = .idle
    var outputLines: [String] = []
    var progress: Double = 0
    var showDetails: Bool = false
    var detailsLoading: Bool = false
    var installTarget: String = "/"
    var showLicense: Bool = false

    let helperManager = HelperManager()
    private let settings = AppSettings.shared

    private let xpcClient = XPCClient()
    private let directInstaller = DirectInstaller()

    init() {
        let outputHandler: (String) -> Void = { [weak self] line in
            Task { @MainActor in
                self?.handleOutputLine(line)
            }
        }
        xpcClient.onOutputLine = outputHandler
        directInstaller.onOutputLine = outputHandler
    }

    // MARK: - Actions

    func loadPackage(url: URL) {
        showDetails = false

        if !settings.confirmBeforeInstall {
            state = .inspecting(url)
            Task {
                do {
                    let info = try await PackageInspector.inspectQuick(url: url)
                    install(package: info)
                } catch {
                    state = .failed(
                        PackageInfo(fileURL: url, fileName: url.lastPathComponent, fileSize: 0),
                        errorMessage: error.localizedDescription
                    )
                }
            }
            return
        }

        state = .inspecting(url)
        Task {
            do {
                let info = try await PackageInspector.inspectQuick(url: url)
                state = .packageReady(info)
                // Start loading details in the background immediately
                loadDetails()
            } catch {
                state = .failed(
                    PackageInfo(fileURL: url, fileName: url.lastPathComponent, fileSize: 0),
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    func loadDetails() {
        guard case .packageReady(var info) = state, !info.detailsLoaded else { return }
        detailsLoading = true
        Task {
            await PackageInspector.inspectDetails(info: &info)
            detailsLoading = false
            state = .packageReady(info)
        }
    }

    func install(package info: PackageInfo) {
        state = .installing(info)
        outputLines = []
        progress = 0

        Task {
            var result: (Bool, String)

            if settings.preferHelperDaemon && helperManager.isHelperInstalled {
                result = await xpcClient.installPackage(atPath: info.fileURL.path)
                if !result.0 && result.1.contains("XPC connection error") {
                    outputLines.append("[BoxCutter] Helper unreachable, prompting for password...")
                    result = await directInstaller.installPackage(atPath: info.fileURL.path, target: installTarget)
                }
            } else {
                result = await directInstaller.installPackage(atPath: info.fileURL.path, target: installTarget)
            }

            if result.0 {
                if settings.trashAfterInstall {
                    try? FileManager.default.trashItem(at: info.fileURL, resultingItemURL: nil)
                }
                if settings.playSoundOnComplete {
                    NSSound(named: NSSound.Name(settings.completionSound))?.play()
                }
                state = .completed(info)

                if settings.autoCloseAfterInstall {
                    try? await Task.sleep(for: .seconds(settings.autoCloseDelay))
                    NSApplication.shared.terminate(nil)
                }
            } else {
                if settings.playSoundOnComplete {
                    NSSound(named: NSSound.Name("Basso"))?.play()
                }
                state = .failed(info, errorMessage: result.1)
            }
        }
    }

    func reset() {
        state = .idle
        outputLines = []
        progress = 0
        showDetails = false
        showLicense = false
        installTarget = "/"
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pkg")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            loadPackage(url: url)
        }
    }

    func installHelper() {
        do {
            try helperManager.installHelper()
        } catch {
            // Helper install failed
        }
    }

    // MARK: - Private

    private func handleOutputLine(_ line: String) {
        let sublines = line.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        for subline in sublines where !subline.isEmpty {
            outputLines.append(subline)
            parseProgress(from: subline)
        }
    }

    private func parseProgress(from line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: #"installer:%(\d+\.?\d*)"#, options: .regularExpression) {
            let match = trimmed[range]
            if let numRange = match.range(of: #"\d+\.?\d*"#, options: .regularExpression) {
                if let value = Double(match[numRange]) {
                    let newProgress = min(value / 100.0, 1.0)
                    if newProgress > progress {
                        progress = newProgress
                    }
                }
            }
        }
    }
}
