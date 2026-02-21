import Foundation
import ServiceManagement
import SwiftUI

@Observable
@MainActor
class HelperManager {

    static let shared = HelperManager()

    private(set) var isHelperInstalled: Bool = false
    private(set) var needsApproval: Bool = false

    private let daemon = SMAppService.daemon(plistName: "com.hwxnnn.BoxCutter-Helper.plist")
    private var pollingTask: Task<Void, Never>?

    private init() {
        refreshStatus()
    }

    func refreshStatus() {
        let status = daemon.status
        isHelperInstalled = (status == .enabled)
        needsApproval = (status == .requiresApproval)
    }

    var displayStatus: String {
        switch daemon.status {
        case .enabled:          return "Installed & Running"
        case .requiresApproval: return "Needs Approval"
        case .notRegistered:    return "Not Installed"
        case .notFound:         return "Not Found"
        @unknown default:       return "Unknown"
        }
    }

    var statusColor: Color {
        switch daemon.status {
        case .enabled:          return .green
        case .requiresApproval: return .orange
        default:                return .red
        }
    }

    /// Attempts to register the helper daemon.
    /// On macOS 13+, register() always throws "Operation not permitted" until
    /// the user approves in System Settings > Login Items. This is normal —
    /// we never surface the error. The UI banners reflect the actual status.
    func installHelper() {
        try? daemon.unregister()
        try? daemon.register()
        refreshStatus()

        // Poll for up to 30 seconds waiting for the user to approve in System Settings.
        pollingTask?.cancel()
        pollingTask = Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                refreshStatus()
                if isHelperInstalled { return }
            }
        }
    }

    func uninstallHelper() throws {
        pollingTask?.cancel()
        pollingTask = nil
        try daemon.unregister()
        refreshStatus()
    }
}
