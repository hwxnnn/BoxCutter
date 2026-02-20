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
        var clientCode: SecCode?

        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &clientCode) == errSecSuccess,
              let code = clientCode else {
            return false
        }

        // Get the Helper daemon's own Team ID
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let myself = selfCode else {
            return false
        }

        var selfInfo: CFDictionary?
        // Safely cast SecCode to SecStaticCode using unsafeBitCast since they are bridged
        let staticSelf = unsafeBitCast(myself, to: SecStaticCode.self)
        guard SecCodeCopySigningInformation(staticSelf, SecCSFlags(rawValue: kSecCSRequirementInformation), &selfInfo) == errSecSuccess,
              let infoDict = selfInfo as? [String: Any],
              let teamID = infoDict[kSecCodeInfoTeamIdentifier as String] as? String else {
            return false // Could not determine our own Team ID (e.g. ad-hoc signed)
        }

        // Require the connecting app to be signed by the exact same team
        let requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        var requirement: SecRequirement?
        
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else {
            return false
        }

        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
