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
}

struct DMGInfo: Equatable {
    let dmgURL: URL
    let dmgFileName: String
    let mountPoint: URL
    var apps: [DMGAppEntry]
    var selectedAppIDs: Set<URL>
}

struct InstalledApp: Equatable, Identifiable {
    var id: URL { installedURL }

    let appName: String
    let installedURL: URL
    let bundleIdentifier: String
    let isCodeSigned: Bool
}
