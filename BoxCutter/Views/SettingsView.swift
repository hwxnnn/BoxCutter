import SwiftUI

struct SettingsView: View {

    private enum SettingsPane: String, CaseIterable, Identifiable {
        case general
        case installation
        case output
        case helper
        case advanced

        var id: Self { self }

        var title: String {
            switch self {
            case .general: return "General"
            case .installation: return "Installation"
            case .output: return "Output"
            case .helper: return "Helper"
            case .advanced: return "Advanced"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .installation: return "shippingbox"
            case .output: return "text.justify.left"
            case .helper: return "lock.shield"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

    @Bindable private var settings = AppSettings.shared
    private let helperManager = HelperManager.shared

    @State private var selectedPane: SettingsPane? = .general
    @State private var helperActionError: String?
    @State private var showResetConfirmation = false

    private let sounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    private var activePane: SettingsPane {
        selectedPane ?? .general
    }

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
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 620)
        .toolbar(removing: .sidebarToggle)
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

    private var sidebar: some View {
        List(selection: $selectedPane) {
            ForEach(SettingsPane.allCases) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(Optional(pane))
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        .toolbar(removing: .sidebarToggle)
    }

    private var detail: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch activePane {
                    case .general:
                        generalContent
                    case .installation:
                        installationContent
                    case .output:
                        outputContent
                    case .helper:
                        helperContent
                    case .advanced:
                        advancedContent
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(activePane.title)
                    .font(.headline)
            }
        }
    }

    // MARK: - Pages

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionCard("Window") {
                toggleRow(
                    "Always on top",
                    "Keep BoxCutter above other app windows.",
                    isOn: $settings.alwaysOnTop
                )
            }

            sectionCard("Completion") {
                toggleRow(
                    "Auto close after install",
                    "Close BoxCutter after completion when the app is no longer focused.",
                    isOn: $settings.autoCloseAfterInstall
                )

                if settings.autoCloseAfterInstall {
                    Divider()
                    controlRow("Auto-close delay") {
                        HStack(spacing: 10) {
                            Slider(value: $settings.autoCloseDelay, in: 1...30, step: 1)
                                .frame(width: 190)
                            Text("\(Int(settings.autoCloseDelay))s")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }

                Divider()
                toggleRow(
                    "Play completion sound",
                    "Play a system sound on success or failure.",
                    isOn: $settings.playSoundOnComplete
                )

                if settings.playSoundOnComplete {
                    Divider()
                    controlRow(
                        "Sound",
                        "Pick a sound and preview it instantly."
                    ) {
                        HStack(spacing: 8) {
                            Picker("Completion sound", selection: $settings.completionSound) {
                                ForEach(sounds, id: \.self) { sound in
                                    Text(sound).tag(sound)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)

                            Button {
                                NSSound(named: NSSound.Name(settings.completionSound))?.play()
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .help("Preview selected sound")
                        }
                    }
                }

                Divider()
                toggleRow(
                    "Open installed app automatically (.dmg)",
                    "Open the app after install when the DMG contains one selected app.",
                    isOn: $settings.autoOpenSingleDMGApp
                )

                Divider()
                toggleRow(
                    "Show installed app in Finder automatically (.dmg)",
                    "Reveal the app in Finder after install when the DMG contains one selected app.",
                    isOn: $settings.autoRevealSingleDMGApp
                )
            }
        }
    }

    private var installationContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionCard("Packages (.pkg)") {
                toggleRow(
                    "Confirm before installing",
                    "Ask for confirmation before running the installer.",
                    isOn: $settings.confirmBeforeInstall
                )

                Divider()
                toggleRow(
                    "Move source file to Trash",
                    "Move the original .pkg to Trash after successful install.",
                    isOn: $settings.trashAfterInstall
                )
            }

            sectionCard("Disk Images (.dmg)") {
                toggleRow(
                    "Confirm before installing",
                    "Ask for confirmation before copying apps from the mounted image.",
                    isOn: $settings.confirmBeforeDMGInstall
                )

                Divider()
                toggleRow(
                    "Move source file to Trash",
                    "Move the original .dmg to Trash after successful install.",
                    isOn: $settings.trashDMGAfterInstall
                )
            }

            sectionCard("Safety Preset") {
                controlRow(
                    "Preset",
                    "Choose a baseline, then fine-tune individual options above."
                ) {
                    Picker("Safety preset", selection: safetyProfileBinding) {
                        ForEach(AppSettings.SafetyProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }

            sectionCard("Install Location (.pkg)") {
                toggleRow(
                    "Remember last install location",
                    "Reuse your previous package install target as the next default location.",
                    isOn: $settings.rememberInstallTarget
                )
            }
        }
    }

    private var outputContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionCard("Output Preset") {
                controlRow(
                    "Preset",
                    "Presets only change output options, not install safety settings."
                ) {
                    Picker("Output preset", selection: outputProfileBinding) {
                        ForEach(AppSettings.OutputProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }

            sectionCard("Package Installer View") {
                toggleRow(
                    "Show progress bar",
                    "Display an install progress indicator when available.",
                    isOn: $settings.showProgressBar
                )

                Divider()
                toggleRow(
                    "Show verbose installer output",
                    "Show detailed output from the installer process.",
                    isOn: $settings.showVerboseOutput
                )

                Divider()
                toggleRow(
                    "Warn about install scripts",
                    "Highlight preinstall and postinstall scripts in package details.",
                    isOn: $settings.showScriptWarnings
                )

                Divider()
                toggleRow(
                    "Show payload file list",
                    "Show files that will be installed from the package.",
                    isOn: $settings.showPayloadFiles
                )
            }
        }
    }

    private var helperContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionCard("Helper Status") {
                controlRow("Daemon status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(helperManager.statusColor)
                            .frame(width: 7, height: 7)
                        Text(helperManager.displayStatus)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(helperManager.statusColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(helperManager.statusColor)
                }

                Divider()
                toggleRow(
                    "Prefer helper for installs",
                    "Use the helper daemon before falling back to password prompts.",
                    isOn: $settings.preferHelperDaemon
                )

                if helperManager.needsApproval {
                    Divider()
                    controlRow("Approval required") {
                        Button("Open Login Items") {
                            openLoginItemsSettings()
                        }
                    }
                }
            }

            sectionCard("Actions") {
                HStack(spacing: 10) {
                    Button("Install Helper") { doInstallHelper() }
                        .buttonStyle(.borderedProminent)

                    Button("Uninstall Helper") { doUninstallHelper() }
                        .buttonStyle(.bordered)

                    Spacer()

                    Button("Refresh") {
                        helperActionError = nil
                        helperManager.refreshStatus()
                    }
                    .buttonStyle(.bordered)
                }

                if let helperActionError {
                    Divider()
                    Text(helperActionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            sectionCard("Info") {
                valueRow("Mach service", value: "com.hwxnnn.BoxCutter-Helper")

                Divider()
                HStack {
                    Button("Open Login Items in System Settings") {
                        openLoginItemsSettings()
                    }
                    Spacer()
                }
            }
        }
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionCard("Maintenance") {
                HStack(spacing: 10) {
                    Button("Restore Defaults") {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)

                    Button("Refresh Helper Status") {
                        helperActionError = nil
                        helperManager.refreshStatus()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Actions

    private func doInstallHelper() {
        do {
            try helperManager.installHelper()
            helperActionError = nil
        } catch {
            helperActionError = error.localizedDescription
        }
    }

    private func doUninstallHelper() {
        do {
            try helperManager.uninstallHelper()
            helperActionError = nil
        } catch {
            helperActionError = error.localizedDescription
        }
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Components

    private func sectionCard<C: View>(
        _ title: String,
        @ViewBuilder content: () -> C
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        } label: {
            Text(title)
                .font(.headline)
                .padding(.bottom, 2)
        }
    }

    private func toggleRow(_ title: String, _ description: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func controlRow<C: View>(
        _ title: String,
        _ description: String? = nil,
        @ViewBuilder control: () -> C
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            control()
        }
        .padding(.vertical, 2)
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    SettingsView()
}
