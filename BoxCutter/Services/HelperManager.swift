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

    func installHelper() throws {
        try? daemon.unregister()
        do {
            try daemon.register()
        } catch {
            refreshStatus()
            // macOS 13+ requires user approval in System Settings > Login Items.
            // register() throws "Operation not permitted" while awaiting approval —
            // this is normal, not an error. Only rethrow for actual failures.
            if daemon.status != .requiresApproval {
                throw error
            }
        }
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
