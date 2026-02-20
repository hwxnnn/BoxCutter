import Foundation
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
class AppViewModel {

    var state: AppState = .idle
    var outputLines: [String] = []
    var progress: Double = 0

    let helperManager = HelperManager()

    private let inspector = PackageInspector()
    private let xpcClient = XPCClient()

    init() {
        xpcClient.onOutputLine = { [weak self] line in
            Task { @MainActor in
                self?.handleOutputLine(line)
            }
        }
    }

    // MARK: - Actions

    func loadPackage(url: URL) {
        state = .inspecting(url)
        Task {
            do {
                let info = try await inspector.inspect(url: url)
                state = .packageReady(info)
            } catch {
                state = .failed(
                    PackageInfo(fileURL: url, fileName: url.lastPathComponent, fileSize: 0),
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    func install(package info: PackageInfo) {
        state = .installing(info)
        outputLines = []
        progress = 0

        Task {
            let (success, message) = await xpcClient.installPackage(atPath: info.fileURL.path)
            if success {
                state = .completed(info)
            } else {
                state = .failed(info, errorMessage: message)
            }
        }
    }

    func reset() {
        state = .idle
        outputLines = []
        progress = 0
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.package]
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
            // Helper install failed — state unchanged, banner remains visible
        }
    }

    // MARK: - Private

    private func handleOutputLine(_ line: String) {
        outputLines.append(line)
        if let pct = PackageInspector.parsePercentage(from: line) {
            progress = pct / 100.0
        }
    }
}
