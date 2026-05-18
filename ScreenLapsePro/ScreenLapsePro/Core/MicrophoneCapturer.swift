// ScreenLapsePro
// Core/MicrophoneCapturer.swift
// AVCaptureSession-based microphone capture

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

    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "pro.screenlapse.mic", qos: .userInitiated)

    // MARK: Start

    func start() throws {
        guard let mic = AVCaptureDevice.default(for: .audio) else {
            throw MicError.noDevice
        }
        let input = try AVCaptureDeviceInput(device: mic)

        session.beginConfiguration()
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
        session.stopRunning()
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
