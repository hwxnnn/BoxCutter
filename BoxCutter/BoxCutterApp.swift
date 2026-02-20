import SwiftUI

@main
struct BoxCutterApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 480, minHeight: 400)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 480)

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
