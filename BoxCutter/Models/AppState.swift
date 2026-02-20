import Foundation

enum AppState: Equatable {
    case idle
    case inspecting(URL)
    case packageReady(PackageInfo)
    case installing(PackageInfo)
    case completed(PackageInfo)
    case failed(PackageInfo, errorMessage: String)
}
