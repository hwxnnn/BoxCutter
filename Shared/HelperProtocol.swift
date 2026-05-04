import Foundation

/// Protocol exposed by the helper daemon. The main app calls these methods.
@objc(HelperProtocol)
protocol HelperProtocol {
    /// Lightweight readiness check used before starting a long-running install.
    func ping(withReply reply: @escaping (Bool) -> Void)

    /// Install a .pkg at the given absolute path to the specified target volume.
    /// The helper streams output lines by calling the client's ProgressProtocol.
    /// When done, calls reply with (success, message).
    func installPackage(atPath path: String, target: String, withReply reply: @escaping (Bool, String) -> Void)
}
