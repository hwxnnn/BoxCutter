import Foundation
import Darwin

enum BinaryArchitecture: String, Sendable {
    case arm64
    case x86_64

    /// Hardware capability, so an Intel build running under Rosetta still keeps ARM code.
    nonisolated static var native: Self {
        var supportsARM: Int32 = 0
        var size = MemoryLayout.size(ofValue: supportsARM)
        if sysctlbyname("hw.optional.arm64", &supportsARM, &size, nil, 0) == 0,
           supportsARM == 1 {
            return .arm64
        }
        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }

    nonisolated var unusedCodeName: String {
        self == .arm64 ? "Intel" : "Apple silicon"
    }

    nonisolated var nativeCodeName: String {
        self == .arm64 ? "Apple silicon" : "Intel"
    }
}

enum UniversalStripChoice {
    case no, yes, always
}

struct DMGAppEntry: Equatable, Identifiable {
    var id: URL { appURL }

    let appURL: URL
    let appName: String
    let bundleIdentifier: String
    let bundleVersion: String
    let appSize: Int64
    let fileCount: Int
    let isCodeSigned: Bool
    /// Version of the currently installed copy in /Applications, nil if not installed
    let installedVersion: String?
    /// Immediate subfolder inside the volume, empty when at the root
    let subfolder: String
    /// Non-nil only when the main executable supports both Intel and Apple silicon.
    var thinningArchitecture: BinaryArchitecture? = nil
    var estimatedBytesSaved: Int64 = 0
}

struct DMGPkgEntry: Equatable, Identifiable {
    var id: URL { pkgURL }

    let pkgURL: URL
    let pkgName: String
    let fileSize: Int64
    /// Immediate subfolder inside the volume, empty when at the root
    let subfolder: String
}

struct DMGInfo: Equatable {
    let dmgURL: URL
    let dmgFileName: String
    let mountPoint: URL
    var apps: [DMGAppEntry]
    var pkgs: [DMGPkgEntry]
    var selectedAppIDs: Set<URL>
    var selectedPkgIDs: Set<URL>
    /// Choices for this install; the persistent setting is applied when installation starts.
    var appIDsToThin: Set<URL> = []
    var appIDsWithThinningDecision: Set<URL> = []

    var itemCount: Int { apps.count + pkgs.count }
    var selectedCount: Int { selectedAppIDs.count + selectedPkgIDs.count }

    var selectedApps: [DMGAppEntry] { apps.filter { selectedAppIDs.contains($0.appURL) } }
    var selectedPkgs: [DMGPkgEntry] { pkgs.filter { selectedPkgIDs.contains($0.pkgURL) } }

    var selectedUniversalApps: [DMGAppEntry] { selectedApps.filter { $0.thinningArchitecture != nil } }
    var appsAwaitingThinningDecision: [DMGAppEntry] {
        selectedUniversalApps.filter { !appIDsWithThinningDecision.contains($0.appURL) }
    }

    var universalStripPromptMessage: String {
        let apps = selectedUniversalApps
        let devices = apps.first?.thinningArchitecture == .arm64 ? "Intel" : "Apple Silicon"
        let bytes = apps.reduce(0) { $0 + $1.estimatedBytesSaved }
        let size = bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "disk space"
        let subject = apps.count == 1 ? "This app contains" : "These apps contain"
        return "\(subject) code for \(devices) based Mac devices, which your Mac doesn't need.\n\nWould you like to strip it out to save \(size)?"
    }

    mutating func applyUniversalStripChoice(_ choice: UniversalStripChoice) {
        let ids = Set(selectedUniversalApps.map(\.appURL))
        appIDsWithThinningDecision.formUnion(ids)
        switch choice {
        case .no: appIDsToThin.subtract(ids)
        case .yes, .always: appIDsToThin.formUnion(ids)
        }
    }

    mutating func applyAutomaticThinningPreference() {
        let ids = Set(appsAwaitingThinningDecision.map(\.appURL))
        appIDsToThin.formUnion(ids)
        appIDsWithThinningDecision.formUnion(ids)
    }
}

/// A mounted image that turned out to contain nothing installable. Carries just enough
/// to offer the volume to the user in Finder or unmount it again.
struct DMGVolumeInfo: Equatable {
    let dmgURL: URL
    let dmgFileName: String
    let mountPoint: URL
}

struct InstalledApp: Equatable, Identifiable {
    var id: URL { installedURL }

    let appName: String
    let installedURL: URL
    let bundleIdentifier: String
    let isCodeSigned: Bool
}

struct InstalledPackage: Equatable, Identifiable {
    var id: URL { sourceURL }

    let packageName: String
    let sourceURL: URL
    /// Wall-clock time the privileged install took. Measured on ContinuousClock so a
    /// system clock adjustment mid-install cannot skew it.
    let duration: Duration
    let size: Int64
}
