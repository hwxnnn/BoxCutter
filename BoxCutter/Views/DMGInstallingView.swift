import SwiftUI
import AppKit

struct DMGInstallingView: View {

    let info: DMGInfo
    let progress: [URL: Double]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(selectedApps) { app in
                let pct = progress[app.appURL] ?? 0
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                        .resizable()
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(app.appName)
                                .font(.headline)
                                .lineLimit(1)
                                .foregroundStyle(pct >= 1.0 ? .secondary : .primary)
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
                                    Text("\(formatBytes(Int64(pct * Double(app.appSize)))) / \(formatBytes(app.appSize))")
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
        }
        .padding(16)
    }

    private var selectedApps: [DMGAppEntry] {
        info.apps.filter { info.selectedAppIDs.contains($0.appURL) }
    }

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
                    isCodeSigned: true, installedVersion: nil
                ),
                DMGAppEntry(
                    appURL: URL(fileURLWithPath: "/Volumes/Example/App2.app"),
                    appName: "App2", bundleIdentifier: "com.example.app2",
                    bundleVersion: "1.5", appSize: 80_000_000, fileCount: 2400,
                    isCodeSigned: false, installedVersion: nil
                )
            ],
            selectedAppIDs: [
                URL(fileURLWithPath: "/Volumes/Example/App1.app"),
                URL(fileURLWithPath: "/Volumes/Example/App2.app")
            ]
        ),
        progress: [
            URL(fileURLWithPath: "/Volumes/Example/App1.app"): 1.0,
            URL(fileURLWithPath: "/Volumes/Example/App2.app"): 0.45
        ]
    )
    .frame(width: 400)
}
