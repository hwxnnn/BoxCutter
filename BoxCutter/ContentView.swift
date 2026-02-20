import SwiftUI

struct ContentView: View {

    @State private var viewModel = AppViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Helper status banner
            if viewModel.helperManager.needsApproval {
                approvalBanner
            } else if !viewModel.helperManager.isHelperInstalled {
                helperBanner
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
                    progress: viewModel.progress,
                    showDetails: $viewModel.showDetails
                )

            case .completed(let info):
                CompletionView(
                    success: true,
                    packageName: info.packageName.isEmpty ? info.fileName : info.packageName,
                    message: "Installation completed successfully.",
                    onDone: { viewModel.reset() }
                )

            case .failed(let info, let errorMessage):
                CompletionView(
                    success: false,
                    packageName: info.packageName.isEmpty ? info.fileName : info.packageName,
                    message: errorMessage,
                    onDone: { viewModel.reset() }
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
                    quarantineFixedApps: viewModel.quarantineFixedApps,
                    onDone: { NSApplication.shared.terminate(nil) },
                    onShowInFinder: { app in viewModel.revealInstalledApp(app) },
                    onOpenApp: { app in viewModel.openInstalledApp(app) },
                    onFixQuarantine: { app in viewModel.removeQuarantine(app: app) }
                )

            case .dmgFailed(let errorMessage):
                CompletionView(
                    success: false,
                    packageName: "Disk Image",
                    message: errorMessage,
                    onDone: { viewModel.reset() }
                )
            }
        }
        .frame(width: 400)
        .onAppear {
            AppSettings.shared.applyWindowLevel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { notification in
            if let url = notification.object as? URL {
                viewModel.handleFile(url: url)
            }
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
