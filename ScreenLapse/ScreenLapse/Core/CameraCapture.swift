import Foundation
import AVFoundation
import CoreVideo

final class CameraCapture: NSObject {
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let outputQueue = DispatchQueue(label: "com.screenlapse.camera",
                                            qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()

    private(set) var isRunning = false

    func start() throws {
        guard !isRunning else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            throw NSError(domain: "CameraCapture", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No camera device available"])
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw NSError(domain: "CameraCapture", code: -2)
        }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw NSError(domain: "CameraCapture", code: -3)
        }
        session.addOutput(videoOutput)

        session.commitConfiguration()
        session.startRunning()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        session.stopRunning()
        isRunning = false
        onFrame = nil
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
