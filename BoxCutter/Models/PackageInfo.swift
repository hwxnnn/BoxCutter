import Foundation

struct PackageInfo: Equatable, Identifiable {
    var id: URL { fileURL }

    let fileURL: URL
    let fileName: String
    let fileSize: Int64

    var packageName: String = ""
    var packageIdentifier: String = ""
    var version: String = ""
    var installLocation: String = "/"

    var isSigned: Bool = false
    var signingStatus: String = "Unknown"
    var certificateChain: [String] = []

    var payloadFiles: [String] = []
    var hasPreinstallScript: Bool = false
    var hasPostinstallScript: Bool = false

    /// Whether the expensive detail fields (payloadFiles, scripts) have been loaded
    var detailsLoaded: Bool = false
}
