import Foundation
import ServiceManagement

@Observable
class HelperManager {

    private(set) var isHelperInstalled: Bool = false

    private let daemon = SMAppService.daemon(plistName: "com.hwxnnn.BoxCutter-Helper.plist")

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let status = daemon.status
        isHelperInstalled = (status == .enabled || status == .requiresApproval)
    }

    func installHelper() throws {
        try daemon.register()
        // Status may not be .enabled immediately — macOS may show a
        // "allow in background" notification first, making status .requiresApproval
        refreshStatus()
        // Poll briefly in case status updates after a short delay
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            refreshStatus()
        }
    }

    func uninstallHelper() throws {
        try daemon.unregister()
        refreshStatus()
    }
}
