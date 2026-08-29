import Foundation

/// Result of the readiness handshake performed before a privileged install.
enum HelperProbe {
    /// The helper answered.
    case ready
    /// The helper answered with an XPC-level error. An older resident helper that
    /// predates `ping` looks like this, so the install is still worth attempting.
    case errored(String)
    /// Nothing answered within the deadline — launchd could not start the daemon,
    /// or it is wedged. No install has been started, so it is safe to give up.
    case unreachable(String)
}

@MainActor
class XPCClient {

    /// How long to wait for the readiness probe. Generous because launchd has to
    /// cold-start the daemon on first use after login or after the app is replaced.
    private static let probeTimeout: Duration = .seconds(30)
    /// The diagnostic is a trivial command, so it gets a short leash.
    private static let diagnosticTimeout: Duration = .seconds(10)

    private var connection: NSXPCConnection?

    /// A closure the main app provides to receive streamed output lines.
    var onOutputLine: ((String) -> Void)?
    /// Progress commentary for the phases that produce no installer output, so the
    /// UI is never silent while the helper is being contacted.
    var onStatus: ((String) -> Void)?

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

        onStatus?("Contacting the helper daemon…")

        switch await probeHelper() {
        case .ready:
            onStatus?("Helper ready. Starting installation…")

        case .errored(let message):
            // Most likely an older resident helper that does not implement `ping`;
            // it still services installPackage. Invalidate so launchd moves toward
            // the new on-disk binary, then try the install anyway.
            onStatus?("Helper probe failed (\(message)). Attempting the install anyway…")
            disconnect()
            connect()

        case .unreachable(let message):
            // Nothing replied, so no install was ever started and there is no risk of
            // installing twice. Returning here is what keeps a dead daemon from
            // hanging the UI forever — the caller falls back to the password prompt.
            disconnect()
            onStatus?("\(message) Falling back to the password prompt…")
            return (false, message)
        }

        let once = OnceResume()

        // Deliberately unbounded: a large package can legitimately take many minutes,
        // and timing out here would risk a second install running over the first.
        return await withCheckedContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                once.resume(continuation, returning: (false, "XPC connection error: \(error.localizedDescription)"))
            }) as? HelperProtocol else {
                once.resume(continuation, returning: (false, "Failed to create helper proxy."))
                return
            }
            proxy.installPackage(atPath: path, target: target) { success, message in
                once.resume(continuation, returning: (success, message))
            }
        }
    }

    /// Asks the helper to run a trivial command as root. Proves three things at once:
    /// the daemon launches, it accepts this app as a client, and it really is uid 0.
    func runDiagnostic() async -> (Bool, String) {
        if connection == nil { connect() }

        let once = OnceResume()

        return await withCheckedContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(for: Self.diagnosticTimeout)
                guard !Task.isCancelled else { return }
                await MainActor.run { self.disconnect() }
                once.resume(continuation, returning: (
                    false,
                    "The helper did not respond within \(Self.diagnosticTimeout.seconds) seconds. "
                    + "It may need to be reinstalled, or approved in System Settings."
                ))
            }

            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                timeoutTask.cancel()
                // localizedDescription already ends in a period; trim so the two
                // sentences don't run together as "application.. If".
                let detail = error.localizedDescription
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                once.resume(continuation, returning: (
                    false,
                    "Could not reach the helper: \(detail). "
                    + "If the helper was installed by an older build, reinstall it."
                ))
            }) as? HelperProtocol else {
                timeoutTask.cancel()
                once.resume(continuation, returning: (false, "Failed to create helper proxy."))
                return
            }

            proxy.runDiagnostic { success, message in
                timeoutTask.cancel()
                once.resume(continuation, returning: (success, message))
            }
        }
    }

    // MARK: - Readiness probe

    private func probeHelper() async -> HelperProbe {
        let once = OnceResume()

        return await withCheckedContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(for: Self.probeTimeout)
                guard !Task.isCancelled else { return }
                await MainActor.run { self.disconnect() }
                once.resume(continuation, returning: .unreachable(
                    "The helper daemon did not respond within \(Self.probeTimeout.seconds) seconds."
                ))
            }

            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                timeoutTask.cancel()
                once.resume(continuation, returning: .errored(error.localizedDescription))
            }) as? HelperProtocol else {
                timeoutTask.cancel()
                once.resume(continuation, returning: .errored("Failed to create helper proxy."))
                return
            }

            proxy.ping { isReady in
                timeoutTask.cancel()
                once.resume(continuation, returning: isReady ? .ready : .errored("Helper reported not ready."))
            }
        }
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}

private extension Duration {
    var seconds: Int { Int(components.seconds) }
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
