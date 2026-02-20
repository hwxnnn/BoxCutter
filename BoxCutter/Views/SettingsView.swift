import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @Bindable private var settings = AppSettings.shared
    @State private var selectedTab  = 0
    @State private var helperStatus = "Checking..."
    @State private var helperActionError: String?

    private let daemon = SMAppService.daemon(plistName: "com.hwxnnn.BoxCutter-Helper.plist")

    private let sounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Behavior").tag(1)
                Text("Helper").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case 0:  generalContent
                    case 1:  behaviorContent
                    default: helperContent
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 400)
        .onAppear { refreshHelperStatus() }
    }

    // MARK: - General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Window") {
                row("Always on top") {
                    Toggle("", isOn: $settings.alwaysOnTop).labelsHidden()
                }
            }

            section("After Installation") {
                row("Auto close when done") {
                    Toggle("", isOn: $settings.autoCloseAfterInstall).labelsHidden()
                }
                if settings.autoCloseAfterInstall {
                    rowDivider
                    row("Close after", dimLabel: true) {
                        Picker("", selection: $settings.autoCloseDelay) {
                            Text("1 second").tag(1.0)
                            Text("3 seconds").tag(3.0)
                            Text("5 seconds").tag(5.0)
                            Text("10 seconds").tag(10.0)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }
                rowDivider
                row("Play completion sound") {
                    Toggle("", isOn: $settings.playSoundOnComplete).labelsHidden()
                }
                if settings.playSoundOnComplete {
                    rowDivider
                    row("Sound", dimLabel: true) {
                        HStack(spacing: 6) {
                            Picker("", selection: $settings.completionSound) {
                                ForEach(sounds, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 110)
                            Button {
                                NSSound(named: NSSound.Name(settings.completionSound))?.play()
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Behavior

    private var behaviorContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Packages  ·  .pkg") {
                row("Confirm before installing") {
                    Toggle("", isOn: $settings.confirmBeforeInstall).labelsHidden()
                }
                rowDivider
                row("Move to Trash after install") {
                    Toggle("", isOn: $settings.trashAfterInstall).labelsHidden()
                }
                rowDivider
                row("Show verbose installer output") {
                    Toggle("", isOn: $settings.showVerboseOutput).labelsHidden()
                }
                rowDivider
                row("Show progress bar") {
                    Toggle("", isOn: $settings.showProgressBar).labelsHidden()
                }
                rowDivider
                row("Warn about install scripts") {
                    Toggle("", isOn: $settings.showScriptWarnings).labelsHidden()
                }
                rowDivider
                row("Show payload file list") {
                    Toggle("", isOn: $settings.showPayloadFiles).labelsHidden()
                }
            }

            section("Disk Images  ·  .dmg") {
                row("Confirm before installing") {
                    Toggle("", isOn: $settings.confirmBeforeDMGInstall).labelsHidden()
                }
                rowDivider
                row("Move to Trash after install") {
                    Toggle("", isOn: $settings.trashDMGAfterInstall).labelsHidden()
                }
            }
        }
    }

    // MARK: - Helper

    private var helperContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Privileged Helper Daemon") {
                HStack {
                    Text("Status")
                    Spacer()
                    statusPill
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                rowDivider
                row("Prefer helper over password prompts") {
                    Toggle("", isOn: $settings.preferHelperDaemon).labelsHidden()
                }
            }

            section("Actions") {
                HStack(spacing: 10) {
                    Button("Install Helper") { doInstallHelper() }
                    Button("Uninstall Helper") { doUninstallHelper() }
                    Spacer()
                    Button("Refresh") {
                        helperActionError = nil
                        refreshHelperStatus()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if let error = helperActionError {
                    rowDivider
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }

            section("Info") {
                HStack {
                    Text("Service name")
                    Spacer()
                    Text("com.hwxnnn.BoxCutter-Helper")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                rowDivider
                HStack {
                    Button("Open Login Items in System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
            }
        }
    }

    // MARK: - Status

    private var statusColor: Color {
        switch daemon.status {
        case .enabled:          return .green
        case .requiresApproval: return .orange
        case .notRegistered:    return .red
        case .notFound:         return .red
        @unknown default:       return .gray
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(helperStatus).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1), in: Capsule())
        .foregroundStyle(statusColor)
    }

    private func doInstallHelper() {
        do {
            try? daemon.unregister()
            try daemon.register()
            helperActionError = nil
        } catch {
            helperActionError = error.localizedDescription
        }
        refreshHelperStatus()
    }

    private func doUninstallHelper() {
        do {
            try daemon.unregister()
            helperActionError = nil
        } catch {
            helperActionError = error.localizedDescription
        }
        refreshHelperStatus()
    }

    private func refreshHelperStatus() {
        switch daemon.status {
        case .enabled:          helperStatus = "Installed & Running"
        case .requiresApproval: helperStatus = "Needs Approval"
        case .notRegistered:    helperStatus = "Not Installed"
        case .notFound:         helperStatus = "Not Found"
        @unknown default:       helperStatus = "Unknown"
        }
    }

    // MARK: - Building blocks

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
            )
        }
    }

    private func row<C: View>(
        _ label: String,
        dimLabel: Bool = false,
        @ViewBuilder control: () -> C
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(dimLabel ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var rowDivider: some View {
        Divider().padding(.horizontal, 12)
    }
}

#Preview {
    SettingsView()
}
