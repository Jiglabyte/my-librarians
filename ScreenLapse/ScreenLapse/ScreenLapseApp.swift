import SwiftUI

@main
struct ScreenLapseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.recordingManager)
        }
    }
}
