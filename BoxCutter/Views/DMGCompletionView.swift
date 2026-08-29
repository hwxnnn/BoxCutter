import SwiftUI

struct DMGCompletionView: View {

    let apps: [InstalledApp]
    var packages: [InstalledPackage] = []
    var installErrors: [String] = []
    let quarantineFixedApps: Set<URL>
    let onDone: () -> Void
    let onUninstall: () -> Void
    let onShowInFinder: (InstalledApp) -> Void
    let onOpenApp: (InstalledApp) -> Void
    let onFixQuarantine: (InstalledApp) -> Void

    @State private var showPackageDetails = false

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
                    Text(summary)
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
                if !packages.isEmpty {
                    Button {
                        showPackageDetails.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "magnifyingglass").font(.caption2)
                            Text("Details").font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    // Same treatment as the License sheet: floats over the window
                    // instead of growing it.
                    .popover(isPresented: $showPackageDetails, arrowEdge: .top) {
                        packageDetails
                    }
                }

                if !apps.isEmpty {
                    Button("Uninstall") { onUninstall() }
                        .foregroundStyle(.red)
                        .help("Move the newly installed apps to Trash. Packages cannot be undone.")
                }

                Spacer()

                if let first = apps.first {
                    Button("Show in Finder") { onShowInFinder(first) }
                }

                if apps.count == 1, let only = apps.first {
                    Button("Open") { onOpenApp(only) }
                }

                Button("Done") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// Reads naturally for apps only, packages only, or a mix.
    private var summary: String {
        let appPart: String? = apps.isEmpty
            ? nil
            : (apps.count == 1 ? apps[0].appName : "\(apps.count) apps")
        let pkgPart: String? = packages.isEmpty
            ? nil
            : (packages.count == 1 ? packages[0].packageName : "\(packages.count) packages")

        switch (appPart, pkgPart) {
        case let (app?, pkg?): return "\(app) and \(pkg) installed"
        case let (app?, nil): return apps.count == 1 ? app : "\(app) installed"
        case let (nil, pkg?): return packages.count == 1 ? pkg : "\(pkg) installed"
        case (nil, nil): return "Nothing installed"
        }
    }

    // MARK: - Package details

    private var packageDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(packages) { pkg in
                packageLine(
                    name: pkg.packageName,
                    stats: "\(formatDuration(pkg.duration)), \(formatSize(pkg.size))"
                )
            }

            if packages.count > 1 {
                Divider()
                    .padding(.vertical, 2)
                packageLine(
                    name: "Total:",
                    stats: "took \(formatSeconds(totalSeconds)), \(formatSize(totalSize))"
                )
            }
        }
        .padding(12)
        .frame(width: 380)
    }


    /// Sum of the *rounded* per-package values, not the rounded sum. Two packages of
    /// 7.5s each would otherwise print "7s, 7s, total 15s" and read as bad arithmetic.
    private var totalSeconds: Int {
        packages.reduce(0) { $0 + wholeSeconds($1.duration) }
    }

    private var totalSize: Int64 {
        packages.reduce(0) { $0 + $1.size }
    }

    private func packageLine(name: String, stats: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(stats)
        }
        .font(.system(.caption2, design: .monospaced))
        .textSelection(.enabled)
    }

    private func wholeSeconds(_ duration: Duration) -> Int {
        let components = duration.components
        let fraction = Double(components.attoseconds) / 1e18
        return Int((Double(components.seconds) + fraction).rounded())
    }

    private func formatDuration(_ duration: Duration) -> String {
        formatSeconds(wholeSeconds(duration))
    }

    /// Whole units, largest first: "2h 10m 30s", "1m 20s", "12s".
    private func formatSeconds(_ total: Int) -> String {
        guard total >= 1 else { return "<1s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(seconds)s" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
