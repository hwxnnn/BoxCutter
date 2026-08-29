import SwiftUI
import AppKit

struct DMGAppInfoView: View {

    let info: DMGInfo
    let onCancel: () -> Void
    let onInstall: () -> Void
    let onShow: () -> Void
    let onToggleApp: (DMGAppEntry) -> Void
    let onTogglePkg: (DMGPkgEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            itemList
                .padding(16)

            Divider()
                .padding(.horizontal, 16)

            actionBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Item List

    /// Selection controls only appear when there is an actual choice to make.
    private var isSelectable: Bool { info.itemCount > 1 }

    private var itemList: some View {
        VStack(spacing: 8) {
            ForEach(info.apps) { app in
                appRow(app)
            }
            ForEach(info.pkgs) { pkg in
                pkgRow(pkg)
            }
        }
    }

    private func appRow(_ app: DMGAppEntry) -> some View {
        row(
            isSelected: info.selectedAppIDs.contains(app.appURL),
            icon: Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path)),
            title: app.appName,
            subfolder: app.subfolder,
            onTap: { onToggleApp(app) }
        ) {
            HStack(spacing: 8) {
                Text(formattedSize(app.appSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                versionLabel(for: app)
            }
        } trailing: {
            signBadge(for: app)
        }
    }

    private func pkgRow(_ pkg: DMGPkgEntry) -> some View {
        row(
            isSelected: info.selectedPkgIDs.contains(pkg.pkgURL),
            icon: Image(nsImage: NSWorkspace.shared.icon(forFile: pkg.pkgURL.path)),
            title: pkg.pkgName,
            subfolder: pkg.subfolder,
            onTap: { onTogglePkg(pkg) }
        ) {
            Text(formattedSize(pkg.fileSize))
                .font(.caption)
                .foregroundStyle(.secondary)
        } trailing: {
            Text("Installer")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }

    private func row<Detail: View, Trailing: View>(
        isSelected: Bool,
        icon: Image,
        title: String,
        subfolder: String,
        onTap: @escaping () -> Void,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            if isSelectable {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.gray)
                    .font(.body)
            }

            icon
                .resizable()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    detail()

                    if !subfolder.isEmpty {
                        Label(subfolder, systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            trailing()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectable { onTap() }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)

            Button("Show in Finder") { onShow() }

            Button(installButtonLabel) { onInstall() }
                .keyboardShortcut(.defaultAction)
                .disabled(info.selectedCount == 0)
        }
    }

    // MARK: - Helpers

    private var installButtonLabel: String {
        let selectedApps = info.selectedApps
        // "Update" only reads true when every selected item is a replacement, so a
        // package in the selection keeps the label at "Install".
        guard !selectedApps.isEmpty, info.selectedPkgIDs.isEmpty else { return "Install" }
        return selectedApps.allSatisfy { $0.installedVersion != nil } ? "Update" : "Install"
    }

    @ViewBuilder
    private func versionLabel(for app: DMGAppEntry) -> some View {
        if let installedVer = app.installedVersion {
            // Update available — show old → new
            Text("\(installedVer) → \(app.bundleVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !app.bundleVersion.isEmpty {
            Text(app.bundleVersion)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func signBadge(for app: DMGAppEntry) -> some View {
        HStack(spacing: 3) {
            Image(systemName: app.isCodeSigned ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.caption2)
            Text(app.isCodeSigned ? "Signed" : "Unsigned")
                .font(.caption2)
        }
        .foregroundStyle(app.isCodeSigned ? .green : .orange)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview("App + Package") {
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
                    bundleVersion: "3.1.0",
                    appSize: 125_000_000,
                    fileCount: 3200,
                    isCodeSigned: false,
                    installedVersion: "2.4.0",
                    subfolder: ""
                )
            ],
            pkgs: [
                DMGPkgEntry(
                    pkgURL: URL(fileURLWithPath: "/Volumes/Example/Extras/Drivers.pkg"),
                    pkgName: "Drivers",
                    fileSize: 14_000_000,
                    subfolder: "Extras"
                )
            ],
            selectedAppIDs: [URL(fileURLWithPath: "/Volumes/Example/MyApp.app")],
            selectedPkgIDs: []
        ),
        onCancel: {}, onInstall: {}, onShow: {}, onToggleApp: { _ in }, onTogglePkg: { _ in }
    )
    .frame(width: 400)
}
