import Foundation
import SwiftUI

@Observable
class AppSettings {
    static let shared = AppSettings()

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

    // MARK: - Behavior: PKG

    /// Ask for confirmation before starting .pkg installation
    var confirmBeforeInstall: Bool {
        didSet { UserDefaults.standard.set(confirmBeforeInstall, forKey: "confirmBeforeInstall") }
    }

    /// Trash the original .pkg file after a successful installation
    var trashAfterInstall: Bool {
        didSet { UserDefaults.standard.set(trashAfterInstall, forKey: "trashAfterInstall") }
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

    // MARK: - Helper

    /// Prefer the privileged helper daemon over password prompts
    var preferHelperDaemon: Bool {
        didSet { UserDefaults.standard.set(preferHelperDaemon, forKey: "preferHelperDaemon") }
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        let defaultValues: [String: Any] = [
            "alwaysOnTop": false,
            "autoCloseAfterInstall": false,
            "autoCloseDelay": 3.0,
            "playSoundOnComplete": true,
            "completionSound": "Glass",
            "confirmBeforeInstall": true,
            "trashAfterInstall": true,
            "showVerboseOutput": true,
            "showProgressBar": true,
            "showScriptWarnings": true,
            "showPayloadFiles": true,
            "confirmBeforeDMGInstall": true,
            "trashDMGAfterInstall": true,
            "preferHelperDaemon": true
        ]
        defaults.register(defaults: defaultValues)

        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        autoCloseAfterInstall = defaults.bool(forKey: "autoCloseAfterInstall")
        autoCloseDelay = defaults.double(forKey: "autoCloseDelay")
        playSoundOnComplete = defaults.bool(forKey: "playSoundOnComplete")
        completionSound = defaults.string(forKey: "completionSound") ?? "Glass"
        confirmBeforeInstall = defaults.bool(forKey: "confirmBeforeInstall")
        trashAfterInstall = defaults.bool(forKey: "trashAfterInstall")
        showVerboseOutput = defaults.bool(forKey: "showVerboseOutput")
        showProgressBar = defaults.bool(forKey: "showProgressBar")
        showScriptWarnings = defaults.bool(forKey: "showScriptWarnings")
        showPayloadFiles = defaults.bool(forKey: "showPayloadFiles")
        confirmBeforeDMGInstall = defaults.bool(forKey: "confirmBeforeDMGInstall")
        trashDMGAfterInstall = defaults.bool(forKey: "trashDMGAfterInstall")
        preferHelperDaemon = defaults.bool(forKey: "preferHelperDaemon")
    }
}
