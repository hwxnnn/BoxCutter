import Foundation
import ServiceManagement

@Observable
class HelperManager {

    private(set) var isHelperInstalled: Bool = false

    private let daemon = SMAppService.daemon(plistName: "com.hwxnnn.BoxCutter.Helper.plist")

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        isHelperInstalled = daemon.status == .enabled
    }

    func installHelper() throws {
        try daemon.register()
        refreshStatus()
    }

    func uninstallHelper() throws {
        try daemon.unregister()
        refreshStatus()
    }
}
