import Foundation

@MainActor
class XPCClient {

    private var connection: NSXPCConnection?

    /// A closure the main app provides to receive streamed output lines.
    var onOutputLine: ((String) -> Void)?

    func connect() {
        let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)

        let helperInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.remoteObjectInterface = helperInterface

        let progressInterface = NSXPCInterface(with: ProgressProtocol.self)
        conn.exportedInterface = progressInterface
        conn.exportedObject = ProgressHandler(client: self)

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }

        conn.resume()
        self.connection = conn
    }

    func installPackage(atPath path: String, target: String) async -> (Bool, String) {
        if connection == nil { connect() }

        let once = OnceResume()

        return await withCheckedContinuation { continuation in
            // Start a timeout that invalidates the connection if the helper doesn't respond.
            // Give launchd time to cold-start the daemon on first invocation.
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await MainActor.run { self.disconnect() }
                once.resume(continuation, returning: (false, "Helper did not respond in time."))
            }

            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                timeoutTask.cancel()
                once.resume(continuation, returning: (false, "XPC connection error: \(error.localizedDescription)"))
            }) as? HelperProtocol else {
                timeoutTask.cancel()
                once.resume(continuation, returning: (false, "Failed to create helper proxy."))
                return
            }
            proxy.installPackage(atPath: path, target: target) { success, message in
                timeoutTask.cancel()
                once.resume(continuation, returning: (success, message))
            }
        }
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}

/// Thread-safe guard ensuring a CheckedContinuation is resumed at most once.
private final class OnceResume: @unchecked Sendable {
    private var resumed = false
    private let lock = NSLock()

    func resume<T>(_ continuation: CheckedContinuation<T, Never>, returning value: T) {
        lock.lock()
        let alreadyResumed = resumed
        resumed = true
        lock.unlock()
        guard !alreadyResumed else { return }
        continuation.resume(returning: value)
    }
}

// MARK: - Progress Handler (exported to helper)

private class ProgressHandler: NSObject, ProgressProtocol {
    weak var client: XPCClient?

    init(client: XPCClient) {
        self.client = client
    }

    func outputLine(_ line: String) {
        DispatchQueue.main.async {
            self.client?.onOutputLine?(line)
        }
    }
}
