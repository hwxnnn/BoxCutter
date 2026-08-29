import AppKit

/// Plays the chimes that mark the end of an install.
///
/// `AppSettings.completionSound` holds either `defaultName`, meaning the pair bundled
/// with the app, or the name of a macOS system sound. System-sound selections keep the
/// long-standing behaviour of pairing the chosen sound with Basso for failures, because
/// the picker only ever offered one slot.
enum CompletionSound {

    /// Sentinel stored in preferences for the bundled pair. Also its label in the picker.
    static let defaultName = "Default"

    /// NSSound re-reads the file on every init, so keep the decoded sounds around.
    private static var cache: [String: NSSound] = [:]

    static func playSuccess(_ selection: String) {
        guard selection == defaultName else {
            NSSound(named: NSSound.Name(selection))?.play()
            return
        }
        playBundled("CompletionSuccess")
    }

    static func playFailure(_ selection: String) {
        guard selection == defaultName else {
            NSSound(named: NSSound.Name("Basso"))?.play()
            return
        }
        playBundled("CompletionFailure")
    }

    private static func playBundled(_ resource: String) {
        if let sound = cache[resource] {
            // Restart rather than overlap if two installs finish close together.
            sound.stop()
            sound.play()
            return
        }
        guard let url = Bundle.main.url(forResource: resource, withExtension: "caf"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        cache[resource] = sound
        sound.play()
    }
}
