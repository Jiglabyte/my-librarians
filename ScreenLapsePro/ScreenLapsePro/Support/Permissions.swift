// ScreenLapsePro
// Support/Permissions.swift
// Screen recording permission helpers + SwiftUI permission gate view

import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Free Functions

/// Returns true when the app already holds screen-recording permission.
func checkScreenRecordingPermission() -> Bool {
    CGPreflightScreenCaptureAccess()
}

/// Requests screen-recording permission from the system.
/// If the system dialog has already been shown and denied, opens System Settings
/// so the user can flip the toggle manually.
func requestScreenRecordingPermission() {
    let granted = CGRequestScreenCaptureAccess()
    if !granted {
        openScreenCapturePrivacySettings()
    }
}

private func openScreenCapturePrivacySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
        return
    }
    NSWorkspace.shared.open(url)
}

// MARK: - PermissionView

/// Shown inside the popover when screen-recording permission has not been granted.
/// Presents a card prompting the user to grant access via System Settings.
struct PermissionView: View {

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)

            VStack(spacing: 20) {
                Image(systemName: "lock.screen")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 6) {
                    Text("Screen Recording Access Needed")
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)

                    Text("ScreenLapse Pro needs permission to capture your screen. Your recordings are saved locally and never uploaded.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: requestScreenRecordingPermission) {
                    Label("Open System Settings", systemImage: "gear")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(28)
        }
        .frame(width: 280)
        .padding(.vertical, 8)
    }
}

#if DEBUG
struct PermissionView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionView()
            .frame(width: 320, height: 320)
    }
}
#endif
