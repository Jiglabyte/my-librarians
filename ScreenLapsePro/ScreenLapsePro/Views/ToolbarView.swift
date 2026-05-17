// ScreenLapsePro
// Views/ToolbarView.swift
// Floating pill overlay shown during an active recording session

import SwiftUI

// MARK: - ToolbarView

struct ToolbarView: View {

    @ObservedObject var manager: RecordingManager
    var mode: RecordingMode
    var onStop: () -> Void

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 14) {
            // Recording indicator + badge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulseOpacity)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulseOpacity
                    )
                    .onAppear { pulseOpacity = 0.25 }

                Text(modeBadge)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.red)
            }

            Divider()
                .frame(height: 18)
                .opacity(0.3)

            // Elapsed time
            Text(elapsedFormatted)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            // File size
            Text(manager.fileSize)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Time-lapse projected output
            if mode.isTimeLapse {
                Divider()
                    .frame(height: 18)
                    .opacity(0.3)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Output")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(projectedDuration)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .frame(height: 18)
                .opacity(0.3)

            // Pause placeholder (future feature)
            Button(action: { /* pause — future feature */ }) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Pause (coming soon)")
            .disabled(true)
            .opacity(0.5)

            // Stop button
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Stop Recording")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
        )
        .fixedSize()
    }

    // MARK: - Helpers

    private var modeBadge: String {
        if mode.isTimeLapse {
            return "⏩ \(mode.multiplier)x"
        }
        return "REC"
    }

    private var elapsedFormatted: String {
        let total   = manager.elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Shows what the final video duration will be once sped up.
    private var projectedDuration: String {
        guard mode.isTimeLapse, mode.multiplier > 0 else { return "—" }
        let outputSec = manager.elapsedSeconds / mode.multiplier
        let m = outputSec / 60
        let s = outputSec % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Preview

#if DEBUG
struct ToolbarView_Previews: PreviewProvider {
    static var previews: some View {
        let mgr = RecordingManager()
        ToolbarView(
            manager: mgr,
            mode: .timeLapse(multiplier: 15),
            onStop: {}
        )
        .padding(20)
        .background(Color.gray.opacity(0.3))
    }
}
#endif
