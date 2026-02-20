import SwiftUI

struct DMGCompletionView: View {

    let apps: [InstalledApp]
    var installErrors: [String] = []
    let quarantineFixedApps: Set<URL>
    let onDone: () -> Void
    let onUninstall: () -> Void
    let onShowInFinder: (InstalledApp) -> Void
    let onOpenApp: (InstalledApp) -> Void
    let onFixQuarantine: (InstalledApp) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Installation Complete")
                        .font(.headline)
                    Text(apps.count == 1 ? apps[0].appName : "\(apps.count) apps installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Partial install errors (some apps failed, others succeeded)
            if !installErrors.isEmpty {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(installErrors, id: \.self) { error in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Unsigned app warnings
            let unsignedApps = apps.filter { !$0.isCodeSigned }
            if !unsignedApps.isEmpty {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(unsignedApps) { app in
                        unsignedRow(for: app)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // Action bar
            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Button("Uninstall") { onUninstall() }
                    .foregroundStyle(.red)

                Spacer()

                if let first = apps.first {
                    Button("Show in Finder") { onShowInFinder(first) }
                }

                if apps.count == 1, let only = apps.first {
                    Button("Open App") { onOpenApp(only) }
                }

                Button("Done") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Unsigned row

    private func unsignedRow(for app: InstalledApp) -> some View {
        let isFixed = quarantineFixedApps.contains(app.installedURL)
        return HStack(spacing: 8) {
            Image(systemName: isFixed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(isFixed ? .green : .orange)

            if isFixed {
                Text("\(app.appName): quarantine removed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("\(app.appName) is unsigned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Fix for Launch") { onFixQuarantine(app) }
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isFixed ? Color.clear : Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview("Signed") {
    DMGCompletionView(
        apps: [InstalledApp(
            appName: "MyApp",
            installedURL: URL(fileURLWithPath: "/Applications/MyApp.app"),
            bundleIdentifier: "com.example.myapp",
            isCodeSigned: true
        )],
        quarantineFixedApps: [],
        onDone: {}, onUninstall: {},
        onShowInFinder: { _ in }, onOpenApp: { _ in }, onFixQuarantine: { _ in }
    )
    .frame(width: 400)
}

#Preview("Unsigned") {
    DMGCompletionView(
        apps: [InstalledApp(
            appName: "MyApp",
            installedURL: URL(fileURLWithPath: "/Applications/MyApp.app"),
            bundleIdentifier: "com.example.myapp",
            isCodeSigned: false
        )],
        quarantineFixedApps: [],
        onDone: {}, onUninstall: {},
        onShowInFinder: { _ in }, onOpenApp: { _ in }, onFixQuarantine: { _ in }
    )
    .frame(width: 400)
}
