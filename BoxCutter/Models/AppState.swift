import Foundation

enum AppState: Equatable {
    case idle
    case inspecting(URL)
    case packageReady(PackageInfo)
    case installing(PackageInfo)
    case completed(PackageInfo)
    case failed(PackageInfo, errorMessage: String)

    // DMG flow
    case dmgMounting(URL)
    case dmgReady(DMGInfo)
    case dmgNoApps(DMGVolumeInfo)
    case dmgInstalling(DMGInfo)
    case dmgCompleted([InstalledApp], [InstalledPackage])
    case dmgFailed(errorMessage: String)
}
