import Foundation
import SwiftUI

@Observable
class AppSettings {
    static let shared = AppSettings()

    // MARK: - Installation

    /// Trash the original .pkg file after a successful installation
    var trashAfterInstall: Bool {
        didSet { UserDefaults.standard.set(trashAfterInstall, forKey: "trashAfterInstall") }
    }

    /// Ask for confirmation before starting installation
    var confirmBeforeInstall: Bool {
        didSet { UserDefaults.standard.set(confirmBeforeInstall, forKey: "confirmBeforeInstall") }
    }

    /// Automatically close the app after a successful installation
    var autoCloseAfterInstall: Bool {
        didSet { UserDefaults.standard.set(autoCloseAfterInstall, forKey: "autoCloseAfterInstall") }
    }

    /// Delay in seconds before auto-closing (if enabled)
    var autoCloseDelay: Double {
        didSet { UserDefaults.standard.set(autoCloseDelay, forKey: "autoCloseDelay") }
    }

    // MARK: - Display

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

    // MARK: - Behavior

    /// Prefer the privileged helper daemon over password prompts
    var preferHelperDaemon: Bool {
        didSet { UserDefaults.standard.set(preferHelperDaemon, forKey: "preferHelperDaemon") }
    }

    /// Keep the window on top of other windows during installation
    var floatDuringInstall: Bool {
        didSet { UserDefaults.standard.set(floatDuringInstall, forKey: "floatDuringInstall") }
    }

    /// Play a sound when installation completes
    var playSoundOnComplete: Bool {
        didSet { UserDefaults.standard.set(playSoundOnComplete, forKey: "playSoundOnComplete") }
    }

    /// Notification sound name
    var completionSound: String {
        didSet { UserDefaults.standard.set(completionSound, forKey: "completionSound") }
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        // Register defaults
        let defaultValues: [String: Any] = [
            "trashAfterInstall": true,
            "confirmBeforeInstall": true,
            "autoCloseAfterInstall": false,
            "autoCloseDelay": 3.0,
            "showVerboseOutput": true,
            "showProgressBar": true,
            "showScriptWarnings": true,
            "showPayloadFiles": true,
            "preferHelperDaemon": true,
            "floatDuringInstall": false,
            "playSoundOnComplete": true,
            "completionSound": "Glass"
        ]
        defaults.register(defaults: defaultValues)

        // Load values
        trashAfterInstall = defaults.bool(forKey: "trashAfterInstall")
        confirmBeforeInstall = defaults.bool(forKey: "confirmBeforeInstall")
        autoCloseAfterInstall = defaults.bool(forKey: "autoCloseAfterInstall")
        autoCloseDelay = defaults.double(forKey: "autoCloseDelay")
        showVerboseOutput = defaults.bool(forKey: "showVerboseOutput")
        showProgressBar = defaults.bool(forKey: "showProgressBar")
        showScriptWarnings = defaults.bool(forKey: "showScriptWarnings")
        showPayloadFiles = defaults.bool(forKey: "showPayloadFiles")
        preferHelperDaemon = defaults.bool(forKey: "preferHelperDaemon")
        floatDuringInstall = defaults.bool(forKey: "floatDuringInstall")
        playSoundOnComplete = defaults.bool(forKey: "playSoundOnComplete")
        completionSound = defaults.string(forKey: "completionSound") ?? "Glass"
    }
}
