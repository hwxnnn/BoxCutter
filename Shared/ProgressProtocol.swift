import Foundation

/// Protocol exported by the main app on the XPC connection.
/// The helper daemon calls these methods to stream output back.
@objc(ProgressProtocol)
protocol ProgressProtocol {
    func outputLine(_ line: String)
}
