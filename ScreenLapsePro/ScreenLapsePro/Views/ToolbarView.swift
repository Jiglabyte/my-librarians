// ScreenLapsePro
// Views/ToolbarView.swift
// Floating pill overlay shown during an active recording session

import SwiftUI

// MARK: - ToolbarView

struct ToolbarView: View {

    @ObservedObject var manager: RecordingManager
    var onStop: () -> Void

    @State private var pulseOpacity: Double = 1.0

    private var mode: RecordingMode { manager.currentMode }

    var body: some View {
        HStack(spacing: 14) {

            // Pulsing indicator + mode badge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulseOpacity)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                               value: pulseOpacity)
                    .onAppear { pulseOpacity = 0.25 }

                Text(modeBadge)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.red)
            }

            pillDivider

            // Elapsed time
            Text(elapsedFormatted)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            // File size
            Text(manager.fileSize)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Audio indicators
            if Prefs.recordSystemAudio || Prefs.recordMicrophone {
                pillDivider
                HStack(spacing: 4) {
                    if Prefs.recordSystemAudio {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                    if Prefs.recordMicrophone {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }
            }

            // Time-lapse projected output
            if mode.isTimeLapse {
                pillDivider
                VStack(alignment: .leading, spacing: 1) {
                    Text("Output")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(projectedDuration)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            pillDivider

            // Pause / Resume
            Button(action: togglePause) {
                Image(systemName: manager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(manager.isPaused ? "Resume Recording (⌃⇧P)" : "Pause Recording (⌃⇧P)")

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

    private func togglePause() {
        if manager.isPaused {
            manager.resumeRecording()
        } else {
            manager.pauseRecording()
        }
    }

    private var pillDivider: some View {
        Divider().frame(height: 18).opacity(0.3)
    }

    private var modeBadge: String {
        if manager.isPaused { return "PAUSED" }
        return mode.isTimeLapse ? "⏩ \(mode.multiplier)x" : "REC"
    }

    private var elapsedFormatted: String {
        let total = manager.elapsedSeconds
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var projectedDuration: String {
        guard mode.isTimeLapse, mode.multiplier > 0 else { return "—" }
        let out = manager.elapsedSeconds / mode.multiplier
        return String(format: "%02d:%02d", out / 60, out % 60)
    }
}

// MARK: - Preview

#if DEBUG
struct ToolbarView_Previews: PreviewProvider {
    static var previews: some View {
        let mgr = RecordingManager()
        ToolbarView(manager: mgr, onStop: {})
            .padding(20)
            .background(Color.gray.opacity(0.3))
    }
}
#endif
