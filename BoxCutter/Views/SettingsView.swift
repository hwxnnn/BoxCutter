import SwiftUI

struct SettingsView: View {

    @Bindable private var settings = AppSettings.shared
    private let helperManager = HelperManager.shared

    @State private var helperActionError: String?
    @State private var showResetConfirmation = false
    @State private var helperTestResult: (success: Bool, message: String)?
    @State private var helperTestRunning = false

    private let xpcClient = XPCClient()

    private let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    private var safetyProfileBinding: Binding<AppSettings.SafetyProfile> {
        Binding(
            get: { settings.safetyProfile },
            set: { settings.safetyProfile = $0 }
        )
    }

    private var outputProfileBinding: Binding<AppSettings.OutputProfile> {
        Binding(
            get: { settings.outputProfile },
            set: { settings.outputProfile = $0 }
        )
    }

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }

            installation
                .tabItem { Label("Installation", systemImage: "shippingbox") }

            output
                .tabItem { Label("Output", systemImage: "text.justify.left") }

            permissions
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            advanced
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .onAppear { helperManager.refreshStatus() }
        .confirmationDialog(
            "Restore all settings to defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                settings.resetToDefaults()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset every BoxCutter preference, including helper and output options.")
        }
    }

    // MARK: - Tabs

    private var general: some View {
        settingsForm {
            Section("Window") {
                toggle(
                    "Always on top",
                    "Keep BoxCutter above other app windows.",
                    isOn: $settings.alwaysOnTop
                )
            }

            Section("Completion") {
                toggle(
                    "Auto close after install",
                    "Close BoxCutter after completion when the app is no longer focused.",
                    isOn: $settings.autoCloseAfterInstall
                )

                if settings.autoCloseAfterInstall {
                    LabeledContent("Auto-close delay") {
                        HStack(spacing: 10) {
                            Slider(value: $settings.autoCloseDelay, in: 1...30, step: 1)
                                .frame(width: 150)
                            Text("\(Int(settings.autoCloseDelay))s")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }

                toggle(
                    "Play completion sound",
                    "Play a sound on success or failure.",
                    isOn: $settings.playSoundOnComplete
                )

                if settings.playSoundOnComplete {
                    LabeledContent("Sound") {
                        HStack(spacing: 8) {
                            Picker("Completion sound", selection: $settings.completionSound) {
                                // Bundled pair first, separated from the macOS sounds.
                                Text(CompletionSound.defaultName)
                                    .tag(CompletionSound.defaultName)
                                Divider()
                                ForEach(systemSounds, id: \.self) { sound in
                                    Text(sound).tag(sound)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)

                            Button {
                                CompletionSound.playSuccess(settings.completionSound)
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .help("Preview the success sound")
                        }
                    }
                }
            }

            Section {
                toggle(
                    "Open installed app automatically",
                    "Open the app after install when the image contains one selected app.",
                    isOn: $settings.autoOpenSingleDMGApp
                )

                toggle(
                    "Reveal installed app in Finder",
                    "Show the app in Finder after install when the image contains one selected app.",
                    isOn: $settings.autoRevealSingleDMGApp
                )
            } header: {
                Text("After a Disk Image Install")
            }
        }
    }

    private var installation: some View {
        settingsForm {
            Section {
                Picker("Safety preset", selection: safetyProfileBinding) {
                    ForEach(AppSettings.SafetyProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
            } footer: {
                Text("Choose a baseline, then fine-tune the individual options below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Packages (.pkg)") {
                toggle(
                    "Confirm before installing",
                    "Ask for confirmation before running the installer.",
                    isOn: $settings.confirmBeforeInstall
                )

                toggle(
                    "Move source file to Trash",
                    "Move the original .pkg to Trash after a successful install.",
                    isOn: $settings.trashAfterInstall
                )

                toggle(
                    "Remember last install location",
                    "Reuse your previous package install target as the next default.",
                    isOn: $settings.rememberInstallTarget
                )
            }

            Section("Disk Images (.dmg)") {
                toggle(
                    "Confirm before installing",
                    "Ask for confirmation before copying apps from the mounted image.",
                    isOn: $settings.confirmBeforeDMGInstall
                )

                toggle(
                    "Move source file to Trash",
                    "Move the original .dmg to Trash after a successful install.",
                    isOn: $settings.trashDMGAfterInstall
                )
            }
        }
    }

    private var output: some View {
        settingsForm {
            Section {
                Picker("Output preset", selection: outputProfileBinding) {
                    ForEach(AppSettings.OutputProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
            } footer: {
                Text("Presets change only what BoxCutter displays, never install safety.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Package Installer View") {
                toggle(
                    "Show progress bar",
                    "Display an install progress indicator when available.",
                    isOn: $settings.showProgressBar
                )

                toggle(
                    "Show verbose installer output",
                    "Show detailed output from the installer process.",
                    isOn: $settings.showVerboseOutput
                )

                toggle(
                    "Warn about install scripts",
                    "Highlight preinstall and postinstall scripts in package details.",
                    isOn: $settings.showScriptWarnings
                )

                toggle(
                    "Show payload file list",
                    "List the files a package will install.",
                    isOn: $settings.showPayloadFiles
                )
            }
        }
    }

    private var permissions: some View {
        settingsForm {
            Section {
                Picker("Method", selection: Binding(
                    get: { settings.privilegeMethod },
                    set: { settings.privilegeMethod = $0 }
                )) {
                    ForEach(AppSettings.PrivilegeMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
            } header: {
                Text("Privilege Escalation")
            } footer: {
                Text(settings.privilegeMethod.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.prefersHelper {
                Section("Helper Daemon") {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(helperManager.statusColor)
                                .frame(width: 7, height: 7)
                            Text(helperManager.displayStatus)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(helperManager.statusColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(helperManager.statusColor)
                    }

                    if helperManager.needsApproval {
                        LabeledContent {
                            Button("Open Login Items") { openLoginItemsSettings() }
                        } label: {
                            Text("Approval required")
                            Text("Allow BoxCutter in System Settings \u{203A} Login Items.")
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Install Helper") { doInstallHelper() }
                            .buttonStyle(.borderedProminent)
                            .disabled(helperManager.isHelperInstalled)

                        Button("Uninstall") { doUninstallHelper() }
                            .disabled(!helperManager.isHelperInstalled && !helperManager.needsApproval)

                        Spacer()

                        // Outcome glyph sits immediately left of the button that produced it.
                        // The message lives in the tooltip so the row stays one line.
                        if helperTestRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else if let result = helperTestResult {
                            Image(systemName: result.success
                                  ? "checkmark.circle.fill"
                                  : "xmark.circle.fill")
                                .foregroundStyle(result.success ? .green : .red)
                                .help(result.message)
                        }

                        Button("Test") { runHelperTest() }
                            .disabled(helperTestRunning)
                    }

                    if let helperActionError {
                        Label(helperActionError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var advanced: some View {
        settingsForm {
            Section {
                LabeledContent {
                    Button("Restore Defaults\u{2026}", role: .destructive) {
                        showResetConfirmation = true
                    }
                } label: {
                    Text("Reset all preferences")
                    Text("Returns every option on every tab to its original value.")
                }
            } header: {
                Text("Maintenance")
            }
        }
    }

    // MARK: - Actions

    private func doInstallHelper() {
        helperManager.installHelper()
        helperActionError = nil
    }

    private func doUninstallHelper() {
        do {
            try helperManager.uninstallHelper()
            helperActionError = nil
        } catch {
            helperActionError = error.localizedDescription
        }
    }

    /// Refreshes the daemon status and probes it in one action. Status alone reports
    /// "Installed & Running" even when the daemon cannot be reached, so only the probe
    /// proves the helper actually works.
    private func runHelperTest() {
        helperTestRunning = true
        helperTestResult = nil
        helperActionError = nil

        Task {
            helperManager.refreshStatus()

            // Skip the probe when there is nothing registered to answer it — otherwise
            // the user waits out the full diagnostic timeout for a foregone conclusion.
            guard helperManager.isHelperInstalled else {
                helperTestResult = (
                    false,
                    "Helper is not running (status: \(helperManager.displayStatus)). Install it first."
                )
                helperTestRunning = false
                return
            }

            let result = await xpcClient.runDiagnostic()
            helperTestResult = (result.0, result.1)
            // The probe can itself reveal a stale registration, so re-read the status.
            helperManager.refreshStatus()
            helperTestRunning = false
        }
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Components

    /// Every tab shares one size so switching tabs doesn't resize the window.
    private func settingsForm<C: View>(@ViewBuilder content: () -> C) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 400)
    }

    /// Toggle with a secondary description line, matching System Settings rows.
    private func toggle(_ title: String, _ description: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    SettingsView()
}
