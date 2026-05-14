import Foundation
import AVFoundation
import CoreMedia

final class MicCapture: NSObject {
    var onAudioFrame: ((CMSampleBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let outputQueue = DispatchQueue(label: "com.screenlapse.mic",
                                            qos: .userInitiated)

    private(set) var isRunning = false

    func start() throws {
        guard !isRunning else { return }
        session.beginConfiguration()

        guard let device = AVCaptureDevice.default(for: .audio) else {
            session.commitConfiguration()
            throw NSError(domain: "MicCapture", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No mic device available"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw NSError(domain: "MicCapture", code: -2)
        }
        session.addInput(input)

        audioOutput.setSampleBufferDelegate(self, queue: outputQueue)
        guard session.canAddOutput(audioOutput) else {
            session.commitConfiguration()
            throw NSError(domain: "MicCapture", code: -3)
        }
        session.addOutput(audioOutput)
        session.commitConfiguration()
        session.startRunning()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        session.stopRunning()
        isRunning = false
        onAudioFrame = nil
    }
}

extension MicCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onAudioFrame?(sampleBuffer)
    }
}
