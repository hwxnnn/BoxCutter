import Foundation

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

    var itemCount: Int { apps.count + pkgs.count }
    var selectedCount: Int { selectedAppIDs.count + selectedPkgIDs.count }

    var selectedApps: [DMGAppEntry] { apps.filter { selectedAppIDs.contains($0.appURL) } }
    var selectedPkgs: [DMGPkgEntry] { pkgs.filter { selectedPkgIDs.contains($0.pkgURL) } }
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
