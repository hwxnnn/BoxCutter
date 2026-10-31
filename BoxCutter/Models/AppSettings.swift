import Foundation
import SwiftUI

@Observable
class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    enum UniversalAppThinningMode: String, CaseIterable, Identifiable {
        case ask, always, never

        var id: Self { self }

        var title: String {
            switch self {
            case .ask: return "Ask"
            case .always: return "Always"
            case .never: return "Never"
            }
        }
    }

    enum PrivilegeMethod: String, CaseIterable, Identifiable {
        case helper
        case appleScript

        var id: Self { self }

        var title: String {
            switch self {
            case .helper: return "Helper Daemon"
            case .appleScript: return "Password Prompt"
            }
        }

        var description: String {
            switch self {
            case .helper: return "Experimental — installs packages without password input using a background daemon. Requires one-time approval in System Settings."
            case .appleScript: return "Stable — asks for your administrator password each time a package is installed."
            }
        }
    }

    enum OutputProfile: String, CaseIterable, Identifiable {
        case quiet
        case balanced
        case detailed
        case custom

        var id: Self { self }

        var title: String {
            switch self {
            case .quiet: return "Quiet"
            case .balanced: return "Balanced"
            case .detailed: return "Detailed"
            case .custom: return "Custom"
            }
        }
    }

    // MARK: - General

    /// Keep the window always on top
    var alwaysOnTop: Bool {
        didSet {
            defaults.set(alwaysOnTop, forKey: "alwaysOnTop")
            applyWindowLevel()
        }
    }

    func applyWindowLevel() {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows where window.identifier?.rawValue != "com_apple_SwiftUI_Settings_window" {
                window.level = self.alwaysOnTop ? .floating : .normal
            }
        }
    }

    /// Quit after an automatically opened installed app successfully launches
    var autoCloseAfterInstall: Bool {
        didSet { defaults.set(autoCloseAfterInstall, forKey: "autoCloseAfterInstall") }
    }

    /// Play a sound when installation completes
    var playSoundOnComplete: Bool {
        didSet { defaults.set(playSoundOnComplete, forKey: "playSoundOnComplete") }
    }

    /// Notification sound name
    var completionSound: String {
        didSet { defaults.set(completionSound, forKey: "completionSound") }
    }

    /// Automatically open installed app after a single-app DMG install
    var autoOpenSingleDMGApp: Bool {
        didSet { defaults.set(autoOpenSingleDMGApp, forKey: "autoOpenSingleDMGApp") }
    }

    /// Automatically reveal installed app in Finder after a single-app DMG install
    var autoRevealSingleDMGApp: Bool {
        didSet { defaults.set(autoRevealSingleDMGApp, forKey: "autoRevealSingleDMGApp") }
    }

    // MARK: - Behavior: PKG

    /// Ask for confirmation before starting .pkg installation
    var confirmBeforeInstall: Bool {
        didSet { defaults.set(confirmBeforeInstall, forKey: "confirmBeforeInstall") }
    }

    /// Trash the original .pkg file after a successful installation
    var trashAfterInstall: Bool {
        didSet { defaults.set(trashAfterInstall, forKey: "trashAfterInstall") }
    }

    /// Remember selected package install location between installs
    var rememberInstallTarget: Bool {
        didSet {
            defaults.set(rememberInstallTarget, forKey: "rememberInstallTarget")
            if !rememberInstallTarget {
                lastInstallTarget = "/"
            }
        }
    }

    /// Last selected package install location
    var lastInstallTarget: String {
        didSet {
            let sanitized = Self.sanitizeInstallTarget(lastInstallTarget)
            if sanitized != lastInstallTarget {
                lastInstallTarget = sanitized
                return
            }
            defaults.set(sanitized, forKey: "lastInstallTarget")
        }
    }

    /// Show verbose installer output during installation
    var showVerboseOutput: Bool {
        didSet { defaults.set(showVerboseOutput, forKey: "showVerboseOutput") }
    }

    /// Show the progress bar during installation
    var showProgressBar: Bool {
        didSet { defaults.set(showProgressBar, forKey: "showProgressBar") }
    }

    /// Show script warnings on the package info screen
    var showScriptWarnings: Bool {
        didSet { defaults.set(showScriptWarnings, forKey: "showScriptWarnings") }
    }

    /// Show the payload file list on the package info screen
    var showPayloadFiles: Bool {
        didSet { defaults.set(showPayloadFiles, forKey: "showPayloadFiles") }
    }

    // MARK: - Behavior: DMG

    /// Ask for confirmation before installing a .dmg app
    var confirmBeforeDMGInstall: Bool {
        didSet { defaults.set(confirmBeforeDMGInstall, forKey: "confirmBeforeDMGInstall") }
    }

    /// Trash the original .dmg file after a successful installation
    var trashDMGAfterInstall: Bool {
        didSet { defaults.set(trashDMGAfterInstall, forKey: "trashDMGAfterInstall") }
    }

    /// Ask at installation time, always thin automatically, or retain every architecture.
    var universalAppThinningMode: UniversalAppThinningMode {
        didSet {
            defaults.set(universalAppThinningMode.rawValue, forKey: "universalAppThinningMode")
            hasChosenUniversalAppStripping = true
        }
    }

    /// First-run alert is shown once, unless the preference was already chosen in Settings.
    var hasChosenUniversalAppStripping: Bool {
        didSet { defaults.set(hasChosenUniversalAppStripping, forKey: "hasChosenUniversalAppStripping") }
    }

    // MARK: - Permissions

    /// Preferred method for privilege escalation
    var privilegeMethod: PrivilegeMethod {
        get {
            PrivilegeMethod(rawValue: privilegeMethodRaw) ?? .appleScript
        }
        set {
            privilegeMethodRaw = newValue.rawValue
        }
    }

    private var privilegeMethodRaw: String {
        didSet { defaults.set(privilegeMethodRaw, forKey: "privilegeMethod") }
    }

    /// Convenience: true when the user prefers the helper daemon
    var prefersHelper: Bool { privilegeMethod == .helper }

    /// Whether the first-launch privilege prompt has been shown
    var hasShownFirstLaunchPrompt: Bool {
        didSet { defaults.set(hasShownFirstLaunchPrompt, forKey: "hasShownFirstLaunchPrompt") }
    }

    // MARK: - Presets

    var outputProfile: OutputProfile {
        get {
            switch (showVerboseOutput, showProgressBar, showScriptWarnings, showPayloadFiles) {
            case (false, true, false, false):
                return .quiet
            case (true, true, true, false):
                return .balanced
            case (true, true, true, true):
                return .detailed
            default:
                return .custom
            }
        }
        set {
            switch newValue {
            case .quiet:
                showVerboseOutput = false
                showProgressBar = true
                showScriptWarnings = false
                showPayloadFiles = false
            case .balanced:
                showVerboseOutput = true
                showProgressBar = true
                showScriptWarnings = true
                showPayloadFiles = false
            case .detailed:
                showVerboseOutput = true
                showProgressBar = true
                showScriptWarnings = true
                showPayloadFiles = true
            case .custom:
                break
            }
        }
    }

    func resetToDefaults() {
        alwaysOnTop = false
        autoCloseAfterInstall = false
        playSoundOnComplete = true
        completionSound = CompletionSound.defaultName
        autoOpenSingleDMGApp = false
        autoRevealSingleDMGApp = false
        confirmBeforeInstall = true
        trashAfterInstall = false
        rememberInstallTarget = false
        lastInstallTarget = "/"
        showVerboseOutput = true
        showProgressBar = true
        showScriptWarnings = true
        showPayloadFiles = true
        confirmBeforeDMGInstall = true
        trashDMGAfterInstall = false
        universalAppThinningMode = .ask
        hasChosenUniversalAppStripping = false
        privilegeMethodRaw = PrivilegeMethod.appleScript.rawValue
        hasShownFirstLaunchPrompt = false
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let defaultValues: [String: Any] = [
            "alwaysOnTop": false,
            "autoCloseAfterInstall": false,
            "playSoundOnComplete": true,
            "completionSound": CompletionSound.defaultName,
            "autoOpenSingleDMGApp": false,
            "autoRevealSingleDMGApp": false,
            "confirmBeforeInstall": true,
            "trashAfterInstall": false,
            "rememberInstallTarget": false,
            "lastInstallTarget": "/",
            "showVerboseOutput": true,
            "showProgressBar": true,
            "showScriptWarnings": true,
            "showPayloadFiles": true,
            "confirmBeforeDMGInstall": true,
            "trashDMGAfterInstall": false,
            "hasChosenUniversalAppStripping": false,
            "privilegeMethod": PrivilegeMethod.appleScript.rawValue,
            "hasShownFirstLaunchPrompt": false
        ]
        defaults.register(defaults: defaultValues)

        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        autoCloseAfterInstall = defaults.bool(forKey: "autoCloseAfterInstall")
        playSoundOnComplete = defaults.bool(forKey: "playSoundOnComplete")
        completionSound = defaults.string(forKey: "completionSound") ?? CompletionSound.defaultName
        autoOpenSingleDMGApp = defaults.bool(forKey: "autoOpenSingleDMGApp")
        autoRevealSingleDMGApp = defaults.bool(forKey: "autoRevealSingleDMGApp")
        confirmBeforeInstall = defaults.bool(forKey: "confirmBeforeInstall")
        trashAfterInstall = defaults.bool(forKey: "trashAfterInstall")
        rememberInstallTarget = defaults.bool(forKey: "rememberInstallTarget")
        lastInstallTarget = Self.sanitizeInstallTarget(defaults.string(forKey: "lastInstallTarget") ?? "/")
        showVerboseOutput = defaults.bool(forKey: "showVerboseOutput")
        showProgressBar = defaults.bool(forKey: "showProgressBar")
        showScriptWarnings = defaults.bool(forKey: "showScriptWarnings")
        showPayloadFiles = defaults.bool(forKey: "showPayloadFiles")
        confirmBeforeDMGInstall = defaults.bool(forKey: "confirmBeforeDMGInstall")
        trashDMGAfterInstall = defaults.bool(forKey: "trashDMGAfterInstall")
        // Preserve the old toggle's intent without treating Off as the new Never.
        universalAppThinningMode = defaults.string(forKey: "universalAppThinningMode")
            .flatMap(UniversalAppThinningMode.init(rawValue:))
            ?? (defaults.bool(forKey: "stripUniversalApps") ? .always : .ask)
        hasChosenUniversalAppStripping = defaults.bool(forKey: "hasChosenUniversalAppStripping")
        privilegeMethodRaw = defaults.string(forKey: "privilegeMethod") ?? PrivilegeMethod.appleScript.rawValue
        hasShownFirstLaunchPrompt = defaults.bool(forKey: "hasShownFirstLaunchPrompt")
    }

    private static func sanitizeInstallTarget(_ path: String) -> String {
        let normalized = URL(fileURLWithPath: path).standardized.path
        guard normalized.hasPrefix("/"), !normalized.contains("/../"), !normalized.isEmpty else {
            return "/"
        }
        return normalized
    }
}
