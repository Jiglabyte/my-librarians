import SwiftUI

@main
struct ScreenLapseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only app. Settings are managed by AppDelegate via NSWindowController.
        // This placeholder scene satisfies the SwiftUI App requirement.
        Settings { EmptyView() }
    }
}
