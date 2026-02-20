import SwiftUI

@main
struct BoxCutterApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 320, minHeight: 100)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 180)

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let openPackageFile = Notification.Name("openPackageFile")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "pkg" {
            NotificationCenter.default.post(
                name: .openPackageFile,
                object: url
            )
        }
    }
}
