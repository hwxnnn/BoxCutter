import Foundation
import ServiceManagement

@Observable
class HelperManager {

    private(set) var isHelperInstalled: Bool = false
    private(set) var needsApproval: Bool = false
    private(set) var statusDescription: String = "unknown"

    private let daemon = SMAppService.daemon(plistName: "com.hwxnnn.BoxCutter-Helper.plist")

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let status = daemon.status
        switch status {
        case .notRegistered: statusDescription = "notRegistered"
        case .enabled: statusDescription = "enabled"
        case .requiresApproval: statusDescription = "requiresApproval"
        case .notFound: statusDescription = "notFound"
        @unknown default: statusDescription = "unknown(\(status.rawValue))"
        }
        NSLog("[HelperManager] status: %@", statusDescription)
        isHelperInstalled = (status == .enabled)
        needsApproval = (status == .requiresApproval)
    }

    func installHelper() throws {
        // Unregister first to clear any stale registration
        try? daemon.unregister()

        try daemon.register()
        refreshStatus()

        // Poll for status changes (user may need to approve in System Settings)
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(1))
                refreshStatus()
                if isHelperInstalled { break }
            }
        }
    }

    func uninstallHelper() throws {
        try daemon.unregister()
        refreshStatus()
    }
}
