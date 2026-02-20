import Foundation

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
            self?.connection = nil
        }

        conn.resume()
        self.connection = conn
    }

    func installPackage(atPath path: String) async -> (Bool, String) {
        if connection == nil { connect() }

        return await withCheckedContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(returning: (false, "XPC connection error: \(error.localizedDescription)"))
            }) as? HelperProtocol else {
                continuation.resume(returning: (false, "Failed to create helper proxy."))
                return
            }
            proxy.installPackage(atPath: path) { success, message in
                continuation.resume(returning: (success, message))
            }
        }
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
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
