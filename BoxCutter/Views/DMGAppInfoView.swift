import SwiftUI
import AppKit

struct DMGAppInfoView: View {

    let info: DMGInfo
    let onCancel: () -> Void
    let onInstall: () -> Void
    let onShow: () -> Void
    let onToggleApp: (DMGAppEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            appList
                .padding(16)

            Divider()
                .padding(.horizontal, 16)

            actionBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    // MARK: - App List

    private var appList: some View {
        VStack(spacing: 8) {
            ForEach(info.apps) { app in
                appRow(app)
            }
        }
    }

    private func appRow(_ app: DMGAppEntry) -> some View {
        let isSelected = info.selectedAppIDs.contains(app.appURL)
        return HStack(spacing: 10) {
            // Checkbox for multi-app DMGs
            if info.apps.count > 1 {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.gray)
                    .font(.body)
                    .onTapGesture { onToggleApp(app) }
            }

            // App icon
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                .resizable()
                .frame(width: 32, height: 32)

            // App info
            VStack(alignment: .leading, spacing: 3) {
                Text(app.appName)
                    .font(.headline)
                    .lineLimit(1)

                Text(formattedSize(app.appSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if info.apps.count > 1 {
                onToggleApp(app)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)

            Button("Show in Finder") { onShow() }

            Button("Install") { onInstall() }
                .keyboardShortcut(.defaultAction)
                .disabled(info.selectedAppIDs.isEmpty)
        }
    }

    // MARK: - Helpers

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview("Single App") {
    DMGAppInfoView(
        info: DMGInfo(
            dmgURL: URL(fileURLWithPath: "/tmp/Example.dmg"),
            dmgFileName: "Example.dmg",
            mountPoint: URL(fileURLWithPath: "/Volumes/Example"),
            apps: [
                DMGAppEntry(
                    appURL: URL(fileURLWithPath: "/Volumes/Example/MyApp.app"),
                    appName: "MyApp",
                    bundleIdentifier: "com.example.myapp",
                    appSize: 125_000_000,
                    fileCount: 3200
                )
            ],
            selectedAppIDs: [URL(fileURLWithPath: "/Volumes/Example/MyApp.app")]
        ),
        onCancel: {}, onInstall: {}, onShow: {}, onToggleApp: { _ in }
    )
    .frame(width: 400)
}
