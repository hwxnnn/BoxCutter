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
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(app.appName)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            if pct >= 1.0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                Text("\(Int(pct * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        ProgressView(value: pct)
                            .progressViewStyle(.linear)
                    }
                }
            }
        }
        .padding(16)
    }

    private var selectedApps: [DMGAppEntry] {
        info.apps.filter { info.selectedAppIDs.contains($0.appURL) }
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
                    appSize: 50_000_000, fileCount: 1200
                ),
                DMGAppEntry(
                    appURL: URL(fileURLWithPath: "/Volumes/Example/App2.app"),
                    appName: "App2", bundleIdentifier: "com.example.app2",
                    appSize: 80_000_000, fileCount: 2400
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
