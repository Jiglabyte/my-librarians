// ScreenLapsePro
// App/ScreenLapseProApp.swift
// App entry point — menu-bar only, no Dock icon, no window group

import SwiftUI

@main
struct ScreenLapseProApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // A Settings scene is required so SwiftUI doesn't insist on a WindowGroup,
        // but we present our own settings UI from inside the popover.
        Settings {
            EmptyView()
        }
    }
}
