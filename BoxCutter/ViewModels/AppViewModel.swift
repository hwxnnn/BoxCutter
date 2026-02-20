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
    var dmgInstallProgress: [URL: Double] = [:]
    var quarantineFixedApps: Set<URL> = []
    private var currentMountPoint: URL?
    private var autoCloseTask: Task<Void, Never>?

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

    func handleFile(url: URL) {
        if url.pathExtension.lowercased() == "dmg" {
            loadDMG(url: url)
        } else {
            loadPackage(url: url)
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
            } else {
                if settings.playSoundOnComplete {
                    NSSound(named: NSSound.Name("Basso"))?.play()
                }
                state = .failed(info, errorMessage: result.1)
            }
        }
    }

    // MARK: - DMG Flow

    func loadDMG(url: URL) {
        state = .dmgMounting(url)
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let mountPoint = try await DMGService.mount(url: url)
                // findApps does expensive directory traversal — keep it off MainActor
                let apps = try DMGService.findApps(at: mountPoint)
                await MainActor.run {
                    self.currentMountPoint = mountPoint
                    let info = DMGInfo(
                        dmgURL: url,
                        dmgFileName: url.lastPathComponent,
                        mountPoint: mountPoint,
                        apps: apps,
                        selectedAppIDs: apps.count == 1 ? Set([apps[0].appURL]) : Set()
                    )
                    if !self.settings.confirmBeforeDMGInstall && apps.count == 1 {
                        self.state = .dmgReady(info)
                        self.installSelectedApps()
                    } else {
                        self.state = .dmgReady(info)
                    }
                }
            } catch {
                await MainActor.run {
                    if let mp = self.currentMountPoint {
                        DMGService.unmount(mountPoint: mp)
                        self.currentMountPoint = nil
                    }
                    self.state = .dmgFailed(errorMessage: error.localizedDescription)
                }
            }
        }
    }

    func toggleAppSelection(_ app: DMGAppEntry) {
        guard case .dmgReady(var info) = state else { return }
        if info.selectedAppIDs.contains(app.appURL) {
            info.selectedAppIDs.remove(app.appURL)
        } else {
            info.selectedAppIDs.insert(app.appURL)
        }
        state = .dmgReady(info)
    }

    func installSelectedApps() {
        guard case .dmgReady(let info) = state else { return }
        let selected = info.apps.filter { info.selectedAppIDs.contains($0.appURL) }
        guard !selected.isEmpty else { return }

        state = .dmgInstalling(info)
        dmgInstallProgress = Dictionary(uniqueKeysWithValues: selected.map { ($0.appURL, 0.0) })

        Task {
            var installed: [InstalledApp] = []
            var errors: [String] = []

            await withTaskGroup(of: Result<InstalledApp, Error>.self) { group in
                for app in selected {
                    group.addTask {
                        do {
                            let dest = try await DMGService.copyApp(from: app) { pct in
                                Task { @MainActor in
                                    self.dmgInstallProgress[app.appURL] = pct
                                }
                            }
                            return .success(InstalledApp(
                                appName: app.appName,
                                installedURL: dest,
                                bundleIdentifier: app.bundleIdentifier,
                                isCodeSigned: app.isCodeSigned
                            ))
                        } catch {
                            return .failure(error)
                        }
                    }
                }
                for await result in group {
                    switch result {
                    case .success(let app): installed.append(app)
                    case .failure(let error): errors.append(error.localizedDescription)
                    }
                }
            }

            // Unmount and optionally trash
            DMGService.unmount(mountPoint: info.mountPoint)
            currentMountPoint = nil

            if settings.trashDMGAfterInstall {
                try? FileManager.default.trashItem(at: info.dmgURL, resultingItemURL: nil)
            }

            if !installed.isEmpty {
                if settings.playSoundOnComplete {
                    NSSound(named: NSSound.Name(settings.completionSound))?.play()
                }
                state = .dmgCompleted(installed)
            } else {
                if settings.playSoundOnComplete {
                    NSSound(named: NSSound.Name("Basso"))?.play()
                }
                state = .dmgFailed(errorMessage: errors.joined(separator: "\n"))
            }
        }
    }

    func showDMGInFinder() {
        guard case .dmgReady(let info) = state else { return }
        NSWorkspace.shared.open(info.mountPoint)
    }

    func cancelDMG() {
        reset()
    }

    func openInstalledApp(_ app: InstalledApp) {
        NSWorkspace.shared.open(app.installedURL)
    }

    func revealInstalledApp(_ app: InstalledApp) {
        NSWorkspace.shared.selectFile(
            app.installedURL.path,
            inFileViewerRootedAtPath: "/Applications"
        )
    }

    func reset() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        if let mp = currentMountPoint {
            currentMountPoint = nil
            Task.detached { DMGService.unmount(mountPoint: mp) }
        }
        state = .idle
        outputLines = []
        progress = 0
        showDetails = false
        showLicense = false
        installTarget = "/"
        dmgInstallProgress = [:]
        quarantineFixedApps = []
    }

    // MARK: - Focus-based auto-close

    /// Called when the app loses focus. Starts the auto-close countdown if a
    /// completion state is showing and the setting is enabled.
    func appWillResignActive() {
        guard settings.autoCloseAfterInstall else { return }
        let isComplete: Bool
        switch state {
        case .completed, .dmgCompleted: isComplete = true
        default: isComplete = false
        }
        guard isComplete else { return }
        autoCloseTask?.cancel()
        autoCloseTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(settings.autoCloseDelay))
            guard !Task.isCancelled else { return }
            NSApplication.shared.terminate(nil)
        }
    }

    /// Called when the app regains focus. Cancels any pending auto-close countdown.
    func appDidBecomeActive() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
    }

    func uninstallInstalledApps(_ apps: [InstalledApp]) {
        for app in apps {
            try? FileManager.default.trashItem(at: app.installedURL, resultingItemURL: nil)
        }
        reset()
    }

    func removeQuarantine(app: InstalledApp) {
        Task {
            let success = await DMGService.removeQuarantine(at: app.installedURL)
            if success {
                quarantineFixedApps.insert(app.installedURL)
            }
        }
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "pkg")!,
            UTType(filenameExtension: "dmg")!
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            handleFile(url: url)
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
