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
        var clientCode: SecCode?

        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &clientCode) == errSecSuccess,
              let code = clientCode else {
            return false
        }

        // Strategy 1: Check team ID (production builds)
        if let teamID = selfTeamID() {
            let reqStr = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\"" as CFString
            var requirement: SecRequirement?
            if SecRequirementCreateWithString(reqStr, [], &requirement) == errSecSuccess,
               let req = requirement,
               SecCodeCheckValidity(code, [], req) == errSecSuccess {
                return true
            }
        }

        // Strategy 2: Check bundle identifier (development builds where team ID
        // may not be available — e.g. ad-hoc signed helper tools)
        let bundleReq = "identifier \"com.hwxnnn.BoxCutter\" and anchor apple generic" as CFString
        var requirement: SecRequirement?
        if SecRequirementCreateWithString(bundleReq, [], &requirement) == errSecSuccess,
           let req = requirement,
           SecCodeCheckValidity(code, [], req) == errSecSuccess {
            return true
        }

        // Strategy 3: For local Xcode development builds (signed with Apple Development
        // certificate but without anchor apple generic), just check the identifier
        let devReq = "identifier \"com.hwxnnn.BoxCutter\"" as CFString
        var devRequirement: SecRequirement?
        if SecRequirementCreateWithString(devReq, [], &devRequirement) == errSecSuccess,
           let req = devRequirement,
           SecCodeCheckValidity(code, [], req) == errSecSuccess {
            return true
        }

        return false
    }

    /// Extract our own team ID from signing information, if available.
    private func selfTeamID() -> String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let myself = selfCode else {
            return nil
        }
        var staticSelf: SecStaticCode?
        guard SecCodeCopyStaticCode(myself, [], &staticSelf) == errSecSuccess,
              let staticCode = staticSelf else {
            return nil
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSRequirementInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String else {
            return nil
        }
        return teamID
    }
}
