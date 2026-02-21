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
    var installTarget: String = "/" {
        didSet {
            let sanitized = sanitizeInstallTarget(installTarget)
            if sanitized != installTarget {
                installTarget = sanitized
                return
            }
            if settings.rememberInstallTarget {
                settings.lastInstallTarget = sanitized
            }
        }
    }
    var showLicense: Bool = false
    var dmgInstallProgress: [URL: Double] = [:]
    var dmgInstallErrors: [String] = []
    var quarantineFixedApps: Set<URL> = []
    /// When true, "Done" should quit the app instead of returning to idle.
    var shouldQuitOnDone: Bool = false

    private var currentMountPoint: URL?
    private var autoCloseTask: Task<Void, Never>?

    let helperManager = HelperManager.shared
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
        if settings.rememberInstallTarget {
            installTarget = settings.lastInstallTarget
        }
    }

    // MARK: - Actions

    /// I-4: Guard against dropping a new file while an install or mount is in progress.
    func handleFile(url: URL) {
        guard case .idle = state else { return }
        if url.pathExtension.lowercased() == "dmg" {
            loadDMG(url: url)
        } else {
            loadPackage(url: url)
        }
    }

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
            // I-3: User may have cancelled while details were loading — don't resurrect state.
            guard case .packageReady = state else { return }
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
            let resolvedTarget = sanitizeInstallTarget(installTarget)
            if resolvedTarget != installTarget {
                installTarget = resolvedTarget
            }

            // I-2: Pass installTarget through to the helper so the Location picker is respected.
            if settings.prefersHelper && helperManager.isHelperInstalled {
                // Copy to /tmp/ so the root-level helper can read it
                // (TCC blocks root from ~/Downloads, ~/Desktop, etc.)
                let tmpPkg = "/tmp/BoxCutter-\(UUID().uuidString)-\(info.fileURL.lastPathComponent)"
                do {
                    try FileManager.default.copyItem(atPath: info.fileURL.path, toPath: tmpPkg)
                } catch {
                    result = (false, "Failed to prepare package: \(error.localizedDescription)")
                    // skip to the result handling below
                    if !result.0 {
                        outputLines.append("[BoxCutter] \(result.1)")
                    }
                    return
                }
                result = await xpcClient.installPackage(atPath: tmpPkg, target: resolvedTarget)
                try? FileManager.default.removeItem(atPath: tmpPkg)
                if !result.0 {
                    outputLines.append("[BoxCutter] Helper failed (\(result.1)), falling back to password prompt…")
                    result = await directInstaller.installPackage(atPath: info.fileURL.path, target: resolvedTarget)
                }
            } else {
                result = await directInstaller.installPackage(atPath: info.fileURL.path, target: resolvedTarget)
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
            // C-2: Capture mountPoint locally so it's available in the catch block
            // even before currentMountPoint is set on the MainActor.
            var mountPoint: URL?
            do {
                let mp = try await DMGService.mount(url: url)
                mountPoint = mp
                let apps = try DMGService.findApps(at: mp)
                await MainActor.run {
                    self.currentMountPoint = mp
                    let info = DMGInfo(
                        dmgURL: url,
                        dmgFileName: url.lastPathComponent,
                        mountPoint: mp,
                        apps: apps,
                        selectedAppIDs: apps.count == 1 ? Set([apps[0].appURL]) : Set()
                    )
                    // M-8: Hoist the state assignment — both branches set the same value.
                    self.state = .dmgReady(info)
                    if !self.settings.confirmBeforeDMGInstall && apps.count == 1 {
                        self.installSelectedApps()
                    }
                }
            } catch {
                if let mp = mountPoint {
                    DMGService.unmount(mountPoint: mp)
                }
                await MainActor.run {
                    self.currentMountPoint = nil
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
        dmgInstallErrors = []

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

            DMGService.unmount(mountPoint: info.mountPoint)
            currentMountPoint = nil

            if settings.trashDMGAfterInstall {
                try? FileManager.default.trashItem(at: info.dmgURL, resultingItemURL: nil)
            }

            if !installed.isEmpty {
                if settings.playSoundOnComplete {
                    NSSound(named: NSSound.Name(settings.completionSound))?.play()
                }
                // I-5: Preserve any partial errors so the completion view can show them.
                dmgInstallErrors = errors
                state = .dmgCompleted(installed)

                if installed.count == 1, let app = installed.first {
                    if settings.autoRevealSingleDMGApp {
                        revealInstalledApp(app)
                    }
                    if settings.autoOpenSingleDMGApp {
                        openInstalledApp(app)
                    }
                }
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

    func done() {
        if shouldQuitOnDone {
            NSApplication.shared.terminate(nil)
        } else {
            reset()
        }
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
        installTarget = settings.rememberInstallTarget ? settings.lastInstallTarget : "/"
        dmgInstallProgress = [:]
        dmgInstallErrors = []
        quarantineFixedApps = []
        shouldQuitOnDone = false
    }

    // MARK: - Focus-based auto-close

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
        helperManager.installHelper()
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
        // Support both "installer:%percent:42.5" and "installer:%42.5" formats
        if let range = trimmed.range(of: #"installer:%(?:percent:)?(\d+\.?\d*)"#, options: .regularExpression) {
            let match = String(trimmed[range])
            if let numRange = match.range(of: #"\d+\.?\d*"#, options: .regularExpression) {
                if let value = Double(String(match[numRange])) {
                    let newProgress = min(value / 100.0, 1.0)
                    if newProgress > progress {
                        progress = newProgress
                    }
                }
            }
        }
    }

    private func sanitizeInstallTarget(_ target: String) -> String {
        let normalized = URL(fileURLWithPath: target).standardized.path
        guard normalized.hasPrefix("/"),
              !normalized.contains("/../"),
              FileManager.default.fileExists(atPath: normalized) else {
            return "/"
        }
        return normalized
    }
}
