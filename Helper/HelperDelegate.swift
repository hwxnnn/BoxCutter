import Foundation
import Security

class HelperDelegate: NSObject, NSXPCListenerDelegate {

    private var listener: NSXPCListener!

    func run() {
        listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
        listener.delegate = self
        listener.resume()
        RunLoop.current.run()
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard validateClient(connection: newConnection) else {
            return false
        }

        let interface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = InstallerRunner(connection: newConnection)

        let progressInterface = NSXPCInterface(with: ProgressProtocol.self)
        newConnection.remoteObjectInterface = progressInterface

        newConnection.invalidationHandler = {
            // Connection was invalidated
        }

        newConnection.resume()
        return true
    }

    // MARK: - Client Validation

    private func validateClient(connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        var code: SecCode?

        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let clientCode = code else {
            return false
        }

        // Require the connecting app is signed by our team
        // Uses identifier + team ID check that works with both dev and distribution signing
        let requirementString = "identifier \"com.hwxnnn.BoxCutter\" and anchor apple generic and certificate leaf[subject.OU] = \"867PL24QLQ\""
        var requirement: SecRequirement?

        if SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
           let req = requirement,
           SecCodeCheckValidity(clientCode, [], req) == errSecSuccess {
            return true
        }

        // Fallback: during development, Xcode-signed apps may use a different anchor.
        // Check just the team ID on any Apple-issued certificate.
        let devRequirement = "anchor apple and certificate leaf[subject.OU] = \"867PL24QLQ\""
        if SecRequirementCreateWithString(devRequirement as CFString, [], &requirement) == errSecSuccess,
           let req = requirement,
           SecCodeCheckValidity(clientCode, [], req) == errSecSuccess {
            return true
        }

        return false
    }
}
