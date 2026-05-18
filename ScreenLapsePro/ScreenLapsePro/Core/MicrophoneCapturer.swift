// ScreenLapsePro
// Core/MicrophoneCapturer.swift
// AVCaptureSession-based microphone capture, safe for repeated start/stop

import AVFoundation
import CoreMedia

// MARK: - Delegate

protocol MicrophoneCapturerDelegate: AnyObject {
    func microphoneCapturer(_ capturer: MicrophoneCapturer,
                            didOutputSample sampleBuffer: CMSampleBuffer)
}

// MARK: - MicrophoneCapturer

final class MicrophoneCapturer: NSObject {

    weak var delegate: MicrophoneCapturerDelegate?

    private let session     = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let queue       = DispatchQueue(label: "pro.screenlapse.mic", qos: .userInitiated)

    // MARK: Start

    /// Configures the session (removing any stale inputs/outputs) and starts running.
    func start() throws {
        guard !session.isRunning else { return }

        // Remove any leftover inputs/outputs from a previous session
        session.beginConfiguration()
        for i in session.inputs  { session.removeInput(i) }
        for o in session.outputs { session.removeOutput(o) }

        guard let mic = AVCaptureDevice.default(for: .audio) else {
            session.commitConfiguration()
            throw MicError.noDevice
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: mic)
        } catch {
            session.commitConfiguration()
            throw error
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }
        audioOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }

        session.commitConfiguration()
        session.startRunning()
    }

    // MARK: Stop

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        // Clear delegate so no callbacks fire after stop
        audioOutput.setSampleBufferDelegate(nil, queue: nil)
    }

    // MARK: Errors

    enum MicError: LocalizedError {
        case noDevice
        var errorDescription: String? {
            "No microphone found. Connect a microphone and try again."
        }
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension MicrophoneCapturer: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        delegate?.microphoneCapturer(self, didOutputSample: sampleBuffer)
    }
}
