import SwiftUI

@main
struct BoxCutterApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .fixedSize()
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .containerBackground(.thickMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 180)

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "pkg" || ext == "dmg" {
                NotificationCenter.default.post(name: .openFile, object: url)
            }
        }
    }
}
