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
        // Validate connecting client's code signature
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

        // Require the connecting app to be signed by the same team
        // Replace TEAMID with your actual Apple Developer Team ID
        let requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"TEAMID\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else {
            return false
        }

        return SecCodeCheckValidity(clientCode, [], req) == errSecSuccess
    }
}
