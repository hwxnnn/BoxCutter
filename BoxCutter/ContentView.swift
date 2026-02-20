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
            Group {
                switch viewModel.state {
                case .idle:
                    DropZoneView(
                        onFileDrop: { url in viewModel.loadPackage(url: url) },
                        onSelectFile: { viewModel.selectFile() }
                    )

                case .inspecting:
                    VStack {
                        Spacer()
                        ProgressView("Inspecting package\u{2026}")
                        Spacer()
                    }

                case .packageReady(let info):
                    PackageInfoView(
                        info: info,
                        onCancel: { viewModel.reset() },
                        onInstall: { viewModel.install(package: info) }
                    )

                case .installing(let info):
                    InstallingView(
                        packageName: info.packageName.isEmpty ? info.fileName : info.packageName,
                        outputLines: viewModel.outputLines,
                        progress: viewModel.progress
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPackageFile)) { notification in
            if let url = notification.object as? URL {
                viewModel.loadPackage(url: url)
            }
        }
    }

    private var approvalBanner: some View {
        HStack {
            Image(systemName: "gear.badge")
                .foregroundStyle(.orange)
            Text("Helper needs approval.")
                .font(.callout)
            Spacer()
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
            }
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08))
    }

    private var helperBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Privileged helper not installed.")
                .font(.callout)
            Spacer()
            Button("Install Helper") {
                viewModel.installHelper()
            }
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.08))
    }
}
