import SwiftUI
import AppKit

struct DMGInstallingView: View {

    let info: DMGInfo
    let progress: [URL: Double]
    /// Packages install sequentially, so only this one is live.
    var activePkgURL: URL?
    var failedPkgURLs: Set<URL> = []

    var body: some View {
        VStack(spacing: 12) {
            ForEach(selectedApps) { app in
                progressRow(
                    icon: NSWorkspace.shared.icon(forFile: app.appURL.path),
                    title: app.appName,
                    pct: progress[app.appURL] ?? 0
                ) { pct in
                    Text("\(formatBytes(Int64(pct * Double(app.appSize)))) / \(formatBytes(app.appSize))")
                }
            }

            ForEach(Array(selectedPkgs.enumerated()), id: \.element.id) { index, pkg in
                pkgRow(
                    pkg,
                    // Packages install one at a time, so the queue position is worth showing.
                    queue: selectedPkgs.count > 1 ? "\(index + 1) of \(selectedPkgs.count)" : nil
                )
            }
        }
        .padding(16)
    }

    // MARK: - Package row

    private enum PkgState { case waiting, installing, installed, failed }

    private func pkgState(_ pkg: DMGPkgEntry) -> PkgState {
        if failedPkgURLs.contains(pkg.pkgURL) { return .failed }
        if (progress[pkg.pkgURL] ?? 0) >= 1.0 { return .installed }
        return pkg.pkgURL == activePkgURL ? .installing : .waiting
    }

    /// Only the live package gets a progress bar. A bar on a queued row reads as
    /// "installing and stuck at 0%", which is exactly what it is not.
    private func pkgRow(_ pkg: DMGPkgEntry, queue: String?) -> some View {
        let state = pkgState(pkg)
        let pct = progress[pkg.pkgURL] ?? 0

        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: pkg.pkgURL.path))
                .resizable()
                .frame(width: 44, height: 44)
                .opacity(state == .waiting ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(pkg.pkgName)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(state == .installing ? .primary : .secondary)

                    if let queue {
                        Text(queue)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    switch state {
                    case .installed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    case .failed:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    case .installing:
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Int(pct * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(formatBytes(pkg.fileSize))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    case .waiting:
                        Text("Waiting\u{2026}")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if state == .installing {
                    ProgressView(value: pct)
                        .progressViewStyle(.linear)
                }
            }
        }
    }

    // MARK: - App row

    private func progressRow<Detail: View>(
        icon: NSImage,
        title: String,
        pct: Double,
        queue: String? = nil,
        @ViewBuilder detail: (Double) -> Detail
    ) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(pct >= 1.0 ? .secondary : .primary)

                    if let queue {
                        Text(queue)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if pct >= 1.0 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Int(pct * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            detail(pct)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                }
                if pct < 1.0 {
                    ProgressView(value: pct)
                        .progressViewStyle(.linear)
                }
            }
        }
    }

    private var selectedApps: [DMGAppEntry] { info.selectedApps }
    private var selectedPkgs: [DMGPkgEntry] { info.selectedPkgs }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    DMGInstallingView(
        info: DMGInfo(
            dmgURL: URL(fileURLWithPath: "/tmp/Example.dmg"),
            dmgFileName: "Example.dmg",
            mountPoint: URL(fileURLWithPath: "/Volumes/Example"),
            apps: [
                DMGAppEntry(
                    appURL: URL(fileURLWithPath: "/Volumes/Example/App1.app"),
                    appName: "App1", bundleIdentifier: "com.example.app1",
                    bundleVersion: "2.0", appSize: 50_000_000, fileCount: 1200,
                    isCodeSigned: true, installedVersion: nil, subfolder: ""
                )
            ],
            pkgs: [
                DMGPkgEntry(
                    pkgURL: URL(fileURLWithPath: "/Volumes/Example/Base.pkg"),
                    pkgName: "Base", fileSize: 24_000_000, subfolder: ""
                ),
                DMGPkgEntry(
                    pkgURL: URL(fileURLWithPath: "/Volumes/Example/Drivers.pkg"),
                    pkgName: "Drivers", fileSize: 8_000_000, subfolder: ""
                )
            ],
            selectedAppIDs: [URL(fileURLWithPath: "/Volumes/Example/App1.app")],
            selectedPkgIDs: [
                URL(fileURLWithPath: "/Volumes/Example/Base.pkg"),
                URL(fileURLWithPath: "/Volumes/Example/Drivers.pkg")
            ]
        ),
        progress: [
            URL(fileURLWithPath: "/Volumes/Example/App1.app"): 1.0,
            URL(fileURLWithPath: "/Volumes/Example/Base.pkg"): 1.0,
            URL(fileURLWithPath: "/Volumes/Example/Drivers.pkg"): 0.18
        ],
        activePkgURL: URL(fileURLWithPath: "/Volumes/Example/Drivers.pkg")
    )
    .frame(width: 400)
}
