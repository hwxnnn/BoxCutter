import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @Bindable private var settings = AppSettings.shared
    @State private var selectedTab: Int = 0
    @State private var helperStatus: String = "Checking..."
    @State private var helperActionError: String?

    private let daemon = SMAppService.daemon(plistName: "com.hwxnnn.BoxCutter-Helper.plist")

    private let sounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Custom segmented tab bar
            segmentedBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            // Tab content
            ScrollView {
                Group {
                    switch selectedTab {
                    case 0:  generalContent
                    case 1:  behaviorContent
                    default: helperContent
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 480, height: 430)
        .onAppear { refreshHelperStatus() }
    }

    // MARK: - Segmented Bar

    private var segmentedBar: some View {
        HStack(spacing: 2) {
            tabSegment("General",  icon: "gearshape.fill",            tag: 0)
            tabSegment("Behavior", icon: "slider.horizontal.3",       tag: 1)
            tabSegment("Helper",   icon: "wrench.and.screwdriver.fill", tag: 2)
        }
        .padding(3)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }

    private func tabSegment(_ title: String, icon: String, tag: Int) -> some View {
        let active = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.13)) { selectedTab = tag }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                active
                    ? AnyShapeStyle(.background)
                    : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(active ? .primary : .secondary)
            .shadow(color: active ? .black.opacity(0.07) : .clear, radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("Window") {
                iconToggle("Always on top",
                           icon: "pin.fill", color: .blue,
                           binding: $settings.alwaysOnTop,
                           detail: "Float above all other windows")
            }

            card("After Installation") {
                iconToggle("Auto close when done",
                           icon: "xmark.circle.fill", color: .orange,
                           binding: $settings.autoCloseAfterInstall)

                if settings.autoCloseAfterInstall {
                    rowDivider
                    indentRow("Close after") {
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

                iconToggle("Play completion sound",
                           icon: "speaker.wave.2.fill", color: .purple,
                           binding: $settings.playSoundOnComplete)

                if settings.playSoundOnComplete {
                    rowDivider
                    indentRow("Sound") {
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
            card("Packages  ·  .pkg") {
                iconToggle("Confirm before installing",
                           icon: "eye.fill", color: .blue,
                           binding: $settings.confirmBeforeInstall)
                rowDivider
                iconToggle("Move to Trash after install",
                           icon: "trash.fill", color: .red,
                           binding: $settings.trashAfterInstall)
                rowDivider
                iconToggle("Show verbose installer output",
                           icon: "text.alignleft", color: Color.blue.opacity(0.75),
                           binding: $settings.showVerboseOutput)
                rowDivider
                iconToggle("Show progress bar",
                           icon: "chart.bar.fill", color: .teal,
                           binding: $settings.showProgressBar)
                rowDivider
                iconToggle("Warn about install scripts",
                           icon: "exclamationmark.triangle.fill", color: .orange,
                           binding: $settings.showScriptWarnings)
                rowDivider
                iconToggle("Show payload file list",
                           icon: "list.bullet.rectangle.fill", color: .gray,
                           binding: $settings.showPayloadFiles)
            }

            card("Disk Images  ·  .dmg") {
                iconToggle("Confirm before installing",
                           icon: "eye.fill", color: .blue,
                           binding: $settings.confirmBeforeDMGInstall)
                rowDivider
                iconToggle("Move to Trash after install",
                           icon: "trash.fill", color: .red,
                           binding: $settings.trashDMGAfterInstall)
            }
        }
    }

    // MARK: - Helper

    private var helperContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("Privileged Helper Daemon") {
                // Status row
                HStack(spacing: 11) {
                    iconBadge(helperStatusIcon, helperStatusColor)
                    Text("Status").font(.body)
                    Spacer()
                    statusPill
                }
                .padding(.horizontal, 12)
                .frame(height: 42)

                rowDivider

                iconToggle("Prefer helper over password prompts",
                           icon: "bolt.fill", color: .yellow,
                           binding: $settings.preferHelperDaemon)
            }

            card("Actions") {
                actionRow("Install Helper",   icon: "arrow.down.circle.fill", color: .green)  { doInstallHelper() }
                rowDivider
                actionRow("Uninstall Helper", icon: "minus.circle.fill",      color: .red)    { doUninstallHelper() }
                rowDivider
                actionRow("Refresh Status",   icon: "arrow.clockwise.circle.fill", color: .blue) {
                    helperActionError = nil
                    refreshHelperStatus()
                }

                if let error = helperActionError {
                    Divider().padding(.leading, 51)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }

            card("Info") {
                HStack(spacing: 11) {
                    iconBadge("tag.fill", .gray)
                    Text("Service name").font(.body)
                    Spacer()
                    Text("com.hwxnnn.BoxCutter-Helper")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .frame(height: 42)

                rowDivider

                actionRow("Login Items in System Settings",
                          icon: "gear.badge", color: .gray, chevron: true) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
                    )
                }
            }
        }
    }

    // MARK: - Helper status

    private var helperStatusColor: Color {
        switch daemon.status {
        case .enabled:          return .green
        case .requiresApproval: return .orange
        case .notRegistered:    return .red
        case .notFound:         return .red
        @unknown default:       return .gray
        }
    }

    private var helperStatusIcon: String {
        switch daemon.status {
        case .enabled:          return "checkmark.shield.fill"
        case .requiresApproval: return "shield.fill"
        default:                return "shield.slash.fill"
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle().fill(helperStatusColor).frame(width: 6, height: 6)
            Text(helperStatus).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(helperStatusColor.opacity(0.12), in: Capsule())
        .foregroundStyle(helperStatusColor)
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

    private func card<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    private func iconToggle(
        _ label: String,
        icon: String,
        color: Color,
        binding: Binding<Bool>,
        detail: String? = nil
    ) -> some View {
        HStack(spacing: 11) {
            iconBadge(icon, color)
            if let detail {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.body)
                    Text(detail).font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                Text(label).font(.body)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden()
        }
        .padding(.horizontal, 12)
        .frame(height: detail != nil ? 52 : 42)
    }

    private func indentRow<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 11) {
            Color.clear.frame(width: 26)
            Text(label).font(.body).foregroundStyle(.secondary)
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func actionRow(
        _ label: String,
        icon: String,
        color: Color,
        chevron: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                iconBadge(icon, color)
                Text(label).font(.body).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconBadge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 6))
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 51)
    }
}

#Preview {
    SettingsView()
}
