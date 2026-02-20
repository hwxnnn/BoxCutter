import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @Bindable private var settings = AppSettings.shared
    @State private var helperStatus: String = "Checking..."
    @State private var helperActionError: String?

    private let daemon = SMAppService.daemon(plistName: "com.hwxnnn.BoxCutter-Helper.plist")

    var body: some View {
        TabView {
            installationTab
                .tabItem { Label("Installation", systemImage: "shippingbox") }

            displayTab
                .tabItem { Label("Display", systemImage: "eye") }

            behaviorTab
                .tabItem { Label("Behavior", systemImage: "gearshape") }

            helperTab
                .tabItem { Label("Helper", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 440, height: 340)
        .onAppear { refreshHelperStatus() }
    }

    // MARK: - Installation Tab

    private var installationTab: some View {
        Form {
            Toggle("Move .pkg to Trash after successful install", isOn: $settings.trashAfterInstall)

            Toggle("Confirm before installing", isOn: $settings.confirmBeforeInstall)

            Divider()

            Toggle("Automatically close after install", isOn: $settings.autoCloseAfterInstall)

            if settings.autoCloseAfterInstall {
                HStack {
                    Text("Close after")
                    Picker("", selection: $settings.autoCloseDelay) {
                        Text("1 second").tag(1.0)
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .padding(.leading, 20)
            }
        }
        .padding()
    }

    // MARK: - Display Tab

    private var displayTab: some View {
        Form {
            Section("During Installation") {
                Toggle("Show verbose installer output", isOn: $settings.showVerboseOutput)
                Toggle("Show progress bar", isOn: $settings.showProgressBar)
            }

            Divider()

            Section("Package Info Screen") {
                Toggle("Show script warnings", isOn: $settings.showScriptWarnings)
                    .help("Warn when a package contains pre-install or post-install scripts")
                Toggle("Show payload file list", isOn: $settings.showPayloadFiles)
            }
        }
        .padding()
    }

    // MARK: - Behavior Tab

    private var behaviorTab: some View {
        Form {
            Toggle("Keep window on top during installation", isOn: $settings.floatDuringInstall)

            Divider()

            Toggle("Play sound when installation completes", isOn: $settings.playSoundOnComplete)

            if settings.playSoundOnComplete {
                Picker("Sound", selection: $settings.completionSound) {
                    Text("Basso").tag("Basso")
                    Text("Blow").tag("Blow")
                    Text("Bottle").tag("Bottle")
                    Text("Frog").tag("Frog")
                    Text("Funk").tag("Funk")
                    Text("Glass").tag("Glass")
                    Text("Hero").tag("Hero")
                    Text("Morse").tag("Morse")
                    Text("Ping").tag("Ping")
                    Text("Pop").tag("Pop")
                    Text("Purr").tag("Purr")
                    Text("Sosumi").tag("Sosumi")
                    Text("Submarine").tag("Submarine")
                    Text("Tink").tag("Tink")
                }
                .frame(width: 200)
                .padding(.leading, 20)

                Button("Preview") {
                    NSSound(named: NSSound.Name(settings.completionSound))?.play()
                }
                .padding(.leading, 20)
            }
        }
        .padding()
    }

    // MARK: - Helper Tab

    private var helperTab: some View {
        Form {
            Section("Privileged Helper Daemon") {
                HStack {
                    Text("Status")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(helperStatusColor)
                            .frame(width: 8, height: 8)
                        Text(helperStatus)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Prefer helper over password prompts", isOn: $settings.preferHelperDaemon)
                    .help("When disabled, BoxCutter always uses password prompts instead of the helper daemon.")
            }

            Divider()

            Section("Actions") {
                HStack(spacing: 12) {
                    Button("Install Helper") {
                        do {
                            try? daemon.unregister()
                            try daemon.register()
                            helperActionError = nil
                        } catch {
                            helperActionError = error.localizedDescription
                        }
                        refreshHelperStatus()
                    }

                    Button("Uninstall Helper") {
                        do {
                            try daemon.unregister()
                            helperActionError = nil
                        } catch {
                            helperActionError = error.localizedDescription
                        }
                        refreshHelperStatus()
                    }

                    Spacer()

                    Button("Refresh") {
                        helperActionError = nil
                        refreshHelperStatus()
                    }
                }

                if let error = helperActionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            Section("Info") {
                HStack {
                    Text("Service name")
                    Spacer()
                    Text("com.hwxnnn.BoxCutter-Helper")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Text("Mach service")
                    Spacer()
                    Text("com.hwxnnn.BoxCutter-Helper")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Open Login Items in System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
            }
        }
        .padding()
    }

    // MARK: - Helper Status

    private var helperStatusColor: Color {
        switch daemon.status {
        case .enabled: return .green
        case .requiresApproval: return .orange
        case .notRegistered: return .red
        case .notFound: return .red
        @unknown default: return .gray
        }
    }

    private func refreshHelperStatus() {
        switch daemon.status {
        case .enabled:
            helperStatus = "Installed & Running"
        case .requiresApproval:
            helperStatus = "Needs Approval"
        case .notRegistered:
            helperStatus = "Not Installed"
        case .notFound:
            helperStatus = "Not Found"
        @unknown default:
            helperStatus = "Unknown"
        }
    }
}

#Preview {
    SettingsView()
}
