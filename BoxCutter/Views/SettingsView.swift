import SwiftUI

struct SettingsView: View {

    @Bindable private var settings = AppSettings.shared

    var body: some View {
        TabView {
            installationTab
                .tabItem { Label("Installation", systemImage: "shippingbox") }

            displayTab
                .tabItem { Label("Display", systemImage: "eye") }

            behaviorTab
                .tabItem { Label("Behavior", systemImage: "gearshape") }
        }
        .frame(width: 420, height: 320)
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

            Divider()

            Toggle("Prefer privileged helper (no password prompt)", isOn: $settings.preferHelperDaemon)
                .help("When enabled, uses the helper daemon for installation. When disabled, always prompts for password.")
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
}

#Preview {
    SettingsView()
}
