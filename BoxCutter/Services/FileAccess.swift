import Foundation

/// macOS gates `~/Desktop`, `~/Documents`, `~/Downloads` and removable volumes behind TCC.
///
/// The permission prompt is raised only for the *responsible* process, and only when that
/// process itself touches the file. BoxCutter does its real work through child tools —
/// `hdiutil`, `installer`, `pkgutil` — which inherit the decision but never trigger the
/// prompt. Without an explicit read from the app first, a file in one of those folders
/// fails silently deep inside a tool and surfaces as a misleading message such as
/// "image not recognized".
enum FileAccess {

    /// Opens the file and reads a single byte so macOS attributes the access to BoxCutter
    /// and shows the Files and Folders prompt if one is needed. Returns false when the
    /// file cannot be read, which for these folders means access was refused.
    nonisolated static func prime(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        // read returns nil only on failure; an empty result is a legitimate empty file.
        return (try? handle.read(upToCount: 1)) != nil
    }

    static func deniedMessage(for url: URL) -> String {
        "BoxCutter can't read \(url.lastPathComponent). Grant access to the folder it is in "
        + "under System Settings \u{203A} Privacy & Security \u{203A} Files and Folders."
    }
}
