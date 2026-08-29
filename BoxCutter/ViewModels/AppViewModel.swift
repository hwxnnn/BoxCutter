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
    /// Set when the package being installed came off a mounted image, so completion
    /// trashes the .dmg the user dropped rather than the .pkg on a read-only volume.
    private var pkgSourceDMG: URL?
    /// The package currently being installed from a DMG queue, so installer progress
    /// lines can be mirrored into that row.
    /// The package currently being installed from a DMG queue. Packages run one at a
    /// time, so everything else in the queue is either finished or still waiting.
    private(set) var activePkgURL: URL?
    /// Packages from the current queue whose install failed, so their row can say so
    /// instead of sitting there looking like it is still queued.
    private(set) var failedPkgURLs: Set<URL> = []

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
        // The helper handshake produces no installer output; without this the UI sits
        // at 0% with an empty log while launchd cold-starts the daemon.
        xpcClient.onStatus = { [weak self] message in
            Task { @MainActor in
                self?.outputLines.append("[BoxCutter] \(message)")
            }
        }
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
        state = .inspecting(url)

        Task {
            // Must happen before any child tool touches the file — see FileAccess.
            guard await Task.detached(operation: { FileAccess.prime(url) }).value else {
                state = .failed(
                    PackageInfo(fileURL: url, fileName: url.lastPathComponent, fileSize: 0),
                    errorMessage: FileAccess.deniedMessage(for: url)
                )
                return
            }

            do {
                let info = try await PackageInspector.inspectQuick(url: url)
                if settings.confirmBeforeInstall {
                    state = .packageReady(info)
                    loadDetails()
                } else {
                    install(package: info)
                }
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
            let resolvedTarget = sanitizeInstallTarget(installTarget)
            if resolvedTarget != installTarget {
                installTarget = resolvedTarget
            }

            let result = await runPrivilegedInstall(pkgURL: info.fileURL, target: resolvedTarget)

            if result.0 {
                disposeOfInstalledSource(pkgURL: info.fileURL)
                if settings.playSoundOnComplete {
                    CompletionSound.playSuccess(settings.completionSound)
                }
                state = .completed(info)
            } else {
                if settings.playSoundOnComplete {
                    CompletionSound.playFailure(settings.completionSound)
                }
                state = .failed(info, errorMessage: result.1)
            }
        }
    }

    /// Helper daemon when preferred and available, AppleScript prompt otherwise.
    /// I-2: installTarget is passed through so the Location picker is respected.
    private func runPrivilegedInstall(pkgURL: URL, target: String) async -> (Bool, String) {
        guard settings.prefersHelper && helperManager.isHelperInstalled else {
            return await directInstaller.installPackage(atPath: pkgURL.path, target: target)
        }

        // Copy to /tmp/ so the root-level helper can read it. TCC blocks root from
        // ~/Downloads and ~/Desktop, and a package may live on a mounted image.
        let tmpPkg = "/tmp/BoxCutter-\(UUID().uuidString)-\(pkgURL.lastPathComponent)"
        do {
            try FileManager.default.copyItem(atPath: pkgURL.path, toPath: tmpPkg)
        } catch {
            let message = "Failed to prepare package: \(error.localizedDescription)"
            outputLines.append("[BoxCutter] \(message)")
            return (false, message)
        }

        var result = await xpcClient.installPackage(atPath: tmpPkg, target: target)
        try? FileManager.default.removeItem(atPath: tmpPkg)

        if !result.0 {
            outputLines.append("[BoxCutter] Helper failed (\(result.1)), falling back to password prompt…")
            result = await directInstaller.installPackage(atPath: pkgURL.path, target: target)
        }
        return result
    }

    /// A package dropped directly is governed by trashAfterInstall. A package that came
    /// off a mounted image lives on a read-only volume, so the image is unmounted and the
    /// .dmg the user actually dropped is what trashDMGAfterInstall applies to.
    private func disposeOfInstalledSource(pkgURL: URL) {
        guard let dmgURL = pkgSourceDMG else {
            if settings.trashAfterInstall {
                try? FileManager.default.trashItem(at: pkgURL, resultingItemURL: nil)
            }
            return
        }

        if let mp = currentMountPoint {
            currentMountPoint = nil
            DMGService.unmount(mountPoint: mp)
        }
        pkgSourceDMG = nil
        if settings.trashDMGAfterInstall {
            try? FileManager.default.trashItem(at: dmgURL, resultingItemURL: nil)
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
                guard FileAccess.prime(url) else {
                    await MainActor.run {
                        self.state = .dmgFailed(errorMessage: FileAccess.deniedMessage(for: url))
                    }
                    return
                }
                let mp = try await DMGService.mount(url: url)
                mountPoint = mp
                let apps = try DMGService.findApps(at: mp)
                let pkgs = try DMGService.findPackages(at: mp)
                if apps.isEmpty && pkgs.isEmpty {
                    // Nothing to install — hand the volume back to the user mounted the way
                    // macOS would on a double-click. remountBrowsable detaches before it
                    // re-attaches, so clear the stale mount point in case the re-attach throws.
                    mountPoint = nil
                    let browsableMountPoint = try await DMGService.remountBrowsable(
                        url: url,
                        currentMountPoint: mp
                    )
                    mountPoint = browsableMountPoint
                    await MainActor.run {
                        self.currentMountPoint = browsableMountPoint
                        self.state = .dmgNoApps(DMGVolumeInfo(
                            dmgURL: url,
                            dmgFileName: url.lastPathComponent,
                            mountPoint: browsableMountPoint
                        ))
                    }
                    return
                }
                if !apps.isEmpty, !pkgs.isEmpty {
                    // Apps are copied, packages are installed — there is no single
                    // sensible action for an image holding both, so hand the whole
                    // volume to Finder and let the user decide.
                    mountPoint = nil
                    let browsableMountPoint = try await DMGService.remountBrowsable(
                        url: url,
                        currentMountPoint: mp
                    )
                    mountPoint = browsableMountPoint
                    await MainActor.run {
                        // Left mounted deliberately; the user is about to work in it.
                        self.currentMountPoint = nil
                        NSWorkspace.shared.open(browsableMountPoint)
                        self.done()
                    }
                    return
                }
                if apps.isEmpty, pkgs.count == 1 {
                    // A lone package gets the full PKG inspection screen — signature,
                    // scripts, payload, install target. The image stays mounted until
                    // the install finishes or the user backs out.
                    await MainActor.run {
                        self.currentMountPoint = mp
                        self.pkgSourceDMG = url
                        self.loadPackage(url: pkgs[0].pkgURL)
                    }
                    return
                }
                await MainActor.run {
                    self.currentMountPoint = mp
                    let onlyApp = apps.count == 1 && pkgs.isEmpty
                    // Mixed images never reach here, so apps and pkgs are mutually
                    // exclusive. Apps are pre-selected because copying them is cheap and
                    // reversible; packages are not, so they stay opt-in.
                    let info = DMGInfo(
                        dmgURL: url,
                        dmgFileName: url.lastPathComponent,
                        mountPoint: mp,
                        apps: apps,
                        pkgs: pkgs,
                        selectedAppIDs: Set(apps.map(\.appURL)),
                        selectedPkgIDs: Set()
                    )
                    // M-8: Hoist the state assignment — both branches set the same value.
                    self.state = .dmgReady(info)
                    if !self.settings.confirmBeforeDMGInstall && onlyApp {
                        self.installSelected()
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

    func togglePkgSelection(_ pkg: DMGPkgEntry) {
        guard case .dmgReady(var info) = state else { return }
        if info.selectedPkgIDs.contains(pkg.pkgURL) {
            info.selectedPkgIDs.remove(pkg.pkgURL)
        } else {
            info.selectedPkgIDs.insert(pkg.pkgURL)
        }
        state = .dmgReady(info)
    }

    func installSelected() {
        guard case .dmgReady(let info) = state else { return }
        let selectedApps = info.selectedApps
        let selectedPkgs = info.selectedPkgs
        guard !selectedApps.isEmpty || !selectedPkgs.isEmpty else { return }

        state = .dmgInstalling(info)
        dmgInstallProgress = Dictionary(
            uniqueKeysWithValues: selectedApps.map { ($0.appURL, 0.0) }
                + selectedPkgs.map { ($0.pkgURL, 0.0) }
        )
        dmgInstallErrors = []
        failedPkgURLs = []
        outputLines = []
        progress = 0

        Task {
            var installed: [InstalledApp] = []
            var installedPackages: [InstalledPackage] = []
            var errors: [String] = []

            // Apps copy concurrently — independent ditto processes, no shared state.
            await withTaskGroup(of: Result<InstalledApp, Error>.self) { group in
                for app in selectedApps {
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

            // Packages run one at a time: each is a privileged `installer` invocation,
            // and with the AppleScript fallback each one raises its own password prompt.
            let resolvedTarget = sanitizeInstallTarget(installTarget)
            for pkg in selectedPkgs {
                activePkgURL = pkg.pkgURL
                progress = 0
                outputLines.append("[BoxCutter] Installing \(pkg.pkgName)…")

                let clock = ContinuousClock()
                let started = clock.now
                let result = await runPrivilegedInstall(pkgURL: pkg.pkgURL, target: resolvedTarget)
                let elapsed = clock.now - started

                if result.0 {
                    dmgInstallProgress[pkg.pkgURL] = 1.0
                    installedPackages.append(InstalledPackage(
                        packageName: pkg.pkgName,
                        sourceURL: pkg.pkgURL,
                        duration: elapsed,
                        size: pkg.fileSize
                    ))
                } else {
                    failedPkgURLs.insert(pkg.pkgURL)
                    errors.append("\(pkg.pkgName): \(result.1)")
                }
            }
            activePkgURL = nil

            DMGService.unmount(mountPoint: info.mountPoint)
            currentMountPoint = nil

            let anySucceeded = !installed.isEmpty || !installedPackages.isEmpty

            // Only discard the source image if something actually installed — a total
            // failure leaves the .dmg in place so the user can retry.
            if anySucceeded && settings.trashDMGAfterInstall {
                try? FileManager.default.trashItem(at: info.dmgURL, resultingItemURL: nil)
            }

            if anySucceeded {
                if settings.playSoundOnComplete {
                    CompletionSound.playSuccess(settings.completionSound)
                }
                // I-5: Preserve any partial errors so the completion view can show them.
                dmgInstallErrors = errors
                state = .dmgCompleted(installed, installedPackages)

                if installed.count == 1, installedPackages.isEmpty, let app = installed.first {
                    if settings.autoRevealSingleDMGApp {
                        revealInstalledApp(app)
                    }
                    if settings.autoOpenSingleDMGApp {
                        openInstalledApp(app)
                    }
                }
            } else {
                if settings.playSoundOnComplete {
                    CompletionSound.playFailure(settings.completionSound)
                }
                state = .dmgFailed(errorMessage: errors.joined(separator: "\n"))
            }
        }
    }

    /// The install flow attaches with `-nobrowse`, so the volume is hidden from Finder.
    /// Re-attach it the way a double-click would, reveal it, and leave it mounted —
    /// the user asked to work with the image, not to install from it.
    func showDMGInFinder() {
        guard case .dmgReady(let info) = state else { return }
        Task {
            do {
                let mountPoint = try await DMGService.remountBrowsable(
                    url: info.dmgURL,
                    currentMountPoint: info.mountPoint
                )
                // Clear first so the reset inside done() doesn't unmount it again.
                currentMountPoint = nil
                NSWorkspace.shared.open(mountPoint)
                done()
            } catch {
                // remountBrowsable detaches before re-attaching, so a failure here
                // means nothing is mounted any more.
                currentMountPoint = nil
                state = .dmgFailed(errorMessage: error.localizedDescription)
            }
        }
    }

    func cancelDMG() {
        reset()
    }

    // MARK: - DMG With No Apps

    // All three actions dismiss via done(). Each clears currentMountPoint first so the
    // reset() inside done() doesn't unmount a volume the user asked to keep.

    /// Leaves the volume mounted.
    func dmgNoAppsClose() {
        currentMountPoint = nil
        done()
    }

    /// Ejects the volume.
    func dmgNoAppsUnmount(_ info: DMGVolumeInfo) {
        currentMountPoint = nil
        DMGService.unmount(mountPoint: info.mountPoint)
        done()
    }

    /// Opens the volume in Finder and leaves it mounted.
    func dmgNoAppsOpen(_ info: DMGVolumeInfo) {
        NSWorkspace.shared.open(info.mountPoint)
        currentMountPoint = nil
        done()
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
        pkgSourceDMG = nil
        activePkgURL = nil
        failedPkgURLs = []
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
                        if let activePkgURL {
                            dmgInstallProgress[activePkgURL] = newProgress
                        }
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
