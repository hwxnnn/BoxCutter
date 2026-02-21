import SwiftUI

struct ContentView: View {

    @State private var viewModel = AppViewModel()
    private let settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // Helper status banner (hidden when user opted out of helper)
            if settings.preferHelperDaemon {
                if viewModel.helperManager.needsApproval {
                    approvalBanner
                } else if !viewModel.helperManager.isHelperInstalled {
                    helperBanner
                }
            }

            // Main content based on state
            switch viewModel.state {
            case .idle:
                DropZoneView(
                    onFileDrop: { url in viewModel.handleFile(url: url) },
                    onSelectFile: { viewModel.selectFile() }
                )

            case .inspecting:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)

            case .packageReady(let info):
                PackageInfoView(
                    info: info,
                    onCancel: { viewModel.reset() },
                    onInstall: { viewModel.install(package: info) },
                    showDetails: $viewModel.showDetails,
                    detailsLoading: viewModel.detailsLoading,
                    installTarget: $viewModel.installTarget,
                    showLicense: $viewModel.showLicense
                )

            case .installing(let info):
                InstallingView(
                    packageName: info.packageName.isEmpty ? info.fileName : info.packageName,
                    outputLines: viewModel.outputLines,
                    progress: $viewModel.progress,
                    showDetails: $viewModel.showDetails
                )

            case .completed(let info):
                CompletionView(
                    success: true,
                    packageName: info.packageName.isEmpty ? info.fileName : info.packageName,
                    message: "Installation completed successfully.",
                    onDone: { viewModel.done() }
                )

            case .failed(let info, let errorMessage):
                CompletionView(
                    success: false,
                    packageName: info.packageName.isEmpty ? info.fileName : info.packageName,
                    message: errorMessage,
                    onDone: { viewModel.done() }
                )

            // DMG states
            case .dmgMounting:
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Mounting disk image\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)

            case .dmgReady(let info):
                DMGAppInfoView(
                    info: info,
                    onCancel: { viewModel.cancelDMG() },
                    onInstall: { viewModel.installSelectedApps() },
                    onShow: { viewModel.showDMGInFinder() },
                    onToggleApp: { app in viewModel.toggleAppSelection(app) }
                )

            case .dmgInstalling(let info):
                DMGInstallingView(
                    info: info,
                    progress: viewModel.dmgInstallProgress
                )

            case .dmgCompleted(let apps):
                DMGCompletionView(
                    apps: apps,
                    installErrors: viewModel.dmgInstallErrors,
                    quarantineFixedApps: viewModel.quarantineFixedApps,
                    onDone: { viewModel.done() },
                    onUninstall: { viewModel.uninstallInstalledApps(apps) },
                    onShowInFinder: { app in viewModel.revealInstalledApp(app) },
                    onOpenApp: { app in viewModel.openInstalledApp(app) },
                    onFixQuarantine: { app in viewModel.removeQuarantine(app: app) }
                )

            case .dmgFailed(let errorMessage):
                CompletionView(
                    success: false,
                    packageName: "Disk Image",
                    message: errorMessage,
                    onDone: { viewModel.done() }
                )
            }
        }
        .frame(width: 400)
        .onAppear {
            settings.applyWindowLevel()
            showFirstLaunchPromptIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { notification in
            if let url = notification.object as? URL {
                viewModel.shouldQuitOnDone = true
                viewModel.handleFile(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            viewModel.appWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.appDidBecomeActive()
        }
    }

    // MARK: - First Launch

    private func showFirstLaunchPromptIfNeeded() {
        guard !settings.hasShownFirstLaunchPrompt else { return }
        settings.hasShownFirstLaunchPrompt = true

        let alert = NSAlert()
        alert.messageText = "Privilege Escalation"
        alert.informativeText = "BoxCutter needs elevated privileges to install packages.\n\nYou can install a helper daemon that runs silently in the background, or use macOS password prompts each time.\n\nThe helper requires your approval in System Settings after installation."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Helper")
        alert.addButton(withTitle: "Use Password Prompts")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            viewModel.installHelper()
            // Open System Settings so the user can approve the daemon immediately
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        } else {
            settings.preferHelperDaemon = false
        }
    }

    // MARK: - Banners

    private var approvalBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "gear.badge").foregroundStyle(.orange).font(.caption)
            Text("Helper needs approval.").font(.caption)
            Spacer()
            Button("System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
            }
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.orange.opacity(0.08))
    }

    private var helperBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.caption)
            Text("Helper not installed.").font(.caption)
            Spacer()
            Button("Install") { viewModel.installHelper() }
                .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.yellow.opacity(0.08))
    }
}
