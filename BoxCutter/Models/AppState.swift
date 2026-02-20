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
    case dmgInstalling(DMGInfo)
    case dmgCompleted([InstalledApp])
    case dmgFailed(errorMessage: String)
}
