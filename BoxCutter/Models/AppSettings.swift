import Foundation
import SwiftUI

@Observable
class AppSettings {
    static let shared = AppSettings()

    enum SafetyProfile: String, CaseIterable, Identifiable {
        case maximum
        case balanced
        case fast
        case custom

        var id: Self { self }

        var title: String {
            switch self {
            case .maximum: return "Maximum Safety"
            case .balanced: return "Balanced"
            case .fast: return "Fast Install"
            case .custom: return "Custom"
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
            UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
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

    /// Automatically close the app after a successful installation
    var autoCloseAfterInstall: Bool {
        didSet { UserDefaults.standard.set(autoCloseAfterInstall, forKey: "autoCloseAfterInstall") }
    }

    /// Delay in seconds before auto-closing (if enabled)
    var autoCloseDelay: Double {
        didSet { UserDefaults.standard.set(autoCloseDelay, forKey: "autoCloseDelay") }
    }

    /// Play a sound when installation completes
    var playSoundOnComplete: Bool {
        didSet { UserDefaults.standard.set(playSoundOnComplete, forKey: "playSoundOnComplete") }
    }

    /// Notification sound name
    var completionSound: String {
        didSet { UserDefaults.standard.set(completionSound, forKey: "completionSound") }
    }

    /// Automatically open installed app after a single-app DMG install
    var autoOpenSingleDMGApp: Bool {
        didSet { UserDefaults.standard.set(autoOpenSingleDMGApp, forKey: "autoOpenSingleDMGApp") }
    }

    /// Automatically reveal installed app in Finder after a single-app DMG install
    var autoRevealSingleDMGApp: Bool {
        didSet { UserDefaults.standard.set(autoRevealSingleDMGApp, forKey: "autoRevealSingleDMGApp") }
    }

    // MARK: - Behavior: PKG

    /// Ask for confirmation before starting .pkg installation
    var confirmBeforeInstall: Bool {
        didSet { UserDefaults.standard.set(confirmBeforeInstall, forKey: "confirmBeforeInstall") }
    }

    /// Trash the original .pkg file after a successful installation
    var trashAfterInstall: Bool {
        didSet { UserDefaults.standard.set(trashAfterInstall, forKey: "trashAfterInstall") }
    }

    /// Remember selected package install location between installs
    var rememberInstallTarget: Bool {
        didSet {
            UserDefaults.standard.set(rememberInstallTarget, forKey: "rememberInstallTarget")
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
            UserDefaults.standard.set(sanitized, forKey: "lastInstallTarget")
        }
    }

    /// Show verbose installer output during installation
    var showVerboseOutput: Bool {
        didSet { UserDefaults.standard.set(showVerboseOutput, forKey: "showVerboseOutput") }
    }

    /// Show the progress bar during installation
    var showProgressBar: Bool {
        didSet { UserDefaults.standard.set(showProgressBar, forKey: "showProgressBar") }
    }

    /// Show script warnings on the package info screen
    var showScriptWarnings: Bool {
        didSet { UserDefaults.standard.set(showScriptWarnings, forKey: "showScriptWarnings") }
    }

    /// Show the payload file list on the package info screen
    var showPayloadFiles: Bool {
        didSet { UserDefaults.standard.set(showPayloadFiles, forKey: "showPayloadFiles") }
    }

    // MARK: - Behavior: DMG

    /// Ask for confirmation before installing a .dmg app
    var confirmBeforeDMGInstall: Bool {
        didSet { UserDefaults.standard.set(confirmBeforeDMGInstall, forKey: "confirmBeforeDMGInstall") }
    }

    /// Trash the original .dmg file after a successful installation
    var trashDMGAfterInstall: Bool {
        didSet { UserDefaults.standard.set(trashDMGAfterInstall, forKey: "trashDMGAfterInstall") }
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
        didSet { UserDefaults.standard.set(privilegeMethodRaw, forKey: "privilegeMethod") }
    }

    /// Convenience: true when the user prefers the helper daemon
    var prefersHelper: Bool { privilegeMethod == .helper }

    /// Whether the first-launch privilege prompt has been shown
    var hasShownFirstLaunchPrompt: Bool {
        didSet { UserDefaults.standard.set(hasShownFirstLaunchPrompt, forKey: "hasShownFirstLaunchPrompt") }
    }

    // MARK: - Presets

    var safetyProfile: SafetyProfile {
        get {
            switch (confirmBeforeInstall, trashAfterInstall, confirmBeforeDMGInstall, trashDMGAfterInstall) {
            case (true, false, true, false):
                return .maximum
            case (true, true, true, true):
                return .balanced
            case (false, true, false, true):
                return .fast
            default:
                return .custom
            }
        }
        set {
            switch newValue {
            case .maximum:
                confirmBeforeInstall = true
                trashAfterInstall = false
                confirmBeforeDMGInstall = true
                trashDMGAfterInstall = false
            case .balanced:
                confirmBeforeInstall = true
                trashAfterInstall = true
                confirmBeforeDMGInstall = true
                trashDMGAfterInstall = true
            case .fast:
                confirmBeforeInstall = false
                trashAfterInstall = true
                confirmBeforeDMGInstall = false
                trashDMGAfterInstall = true
            case .custom:
                break
            }
        }
    }

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
        autoCloseDelay = 3.0
        playSoundOnComplete = true
        completionSound = CompletionSound.defaultName
        autoOpenSingleDMGApp = false
        autoRevealSingleDMGApp = false
        confirmBeforeInstall = true
        trashAfterInstall = true
        rememberInstallTarget = false
        lastInstallTarget = "/"
        showVerboseOutput = true
        showProgressBar = true
        showScriptWarnings = true
        showPayloadFiles = true
        confirmBeforeDMGInstall = true
        trashDMGAfterInstall = true
        privilegeMethodRaw = PrivilegeMethod.appleScript.rawValue
        hasShownFirstLaunchPrompt = false
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        let defaultValues: [String: Any] = [
            "alwaysOnTop": false,
            "autoCloseAfterInstall": false,
            "autoCloseDelay": 3.0,
            "playSoundOnComplete": true,
            "completionSound": CompletionSound.defaultName,
            "autoOpenSingleDMGApp": false,
            "autoRevealSingleDMGApp": false,
            "confirmBeforeInstall": true,
            "trashAfterInstall": true,
            "rememberInstallTarget": false,
            "lastInstallTarget": "/",
            "showVerboseOutput": true,
            "showProgressBar": true,
            "showScriptWarnings": true,
            "showPayloadFiles": true,
            "confirmBeforeDMGInstall": true,
            "trashDMGAfterInstall": true,
            "privilegeMethod": PrivilegeMethod.appleScript.rawValue,
            "hasShownFirstLaunchPrompt": false
        ]
        defaults.register(defaults: defaultValues)

        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        autoCloseAfterInstall = defaults.bool(forKey: "autoCloseAfterInstall")
        autoCloseDelay = defaults.double(forKey: "autoCloseDelay")
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
