import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import CoreMedia
import AppKit

final class FrameCompositor {

    struct Options {
        var webcamCorner: WebcamCorner = .bottomRight
        var webcamRelativeHeight: CGFloat = 0.22
        var webcamMargin: CGFloat = 24
        var drawClickRipples: Bool = false
        var sourceFrameInGlobalCoords: CGRect = .zero
    }

    var options = Options()

    private let context: CIContext
    private var pool: CVPixelBufferPool?
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0

    private var latestCameraBuffer: CVPixelBuffer?
    private let cameraLock = NSLock()

    weak var clickTracker: ClickTracker?

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            self.context = CIContext(mtlDevice: device,
                                     options: [.cacheIntermediates: false])
        } else {
            self.context = CIContext(options: [.cacheIntermediates: false])
        }
    }

    func updateCameraFrame(_ pixelBuffer: CVPixelBuffer) {
        cameraLock.lock()
        latestCameraBuffer = pixelBuffer
        cameraLock.unlock()
    }

    func compose(screenSampleBuffer: CMSampleBuffer,
                 outputWidth: Int,
                 outputHeight: Int,
                 includeWebcam: Bool,
                 includeClicks: Bool) -> CMSampleBuffer? {
        guard let screen = CMSampleBufferGetImageBuffer(screenSampleBuffer) else { return nil }

        let srcWidth = CVPixelBufferGetWidth(screen)
        let srcHeight = CVPixelBufferGetHeight(screen)

        let needsResize = srcWidth != outputWidth || srcHeight != outputHeight
        let needsOverlay = (includeWebcam && hasCameraFrame())
                        || (includeClicks && options.drawClickRipples)

        if !needsResize && !needsOverlay {
            return screenSampleBuffer
        }

        var screenImage = CIImage(cvPixelBuffer: screen)

        if needsResize {
            let sx = CGFloat(outputWidth) / CGFloat(srcWidth)
            let sy = CGFloat(outputHeight) / CGFloat(srcHeight)
            let s = min(sx, sy)
            screenImage = screenImage.transformed(by: CGAffineTransform(scaleX: s, y: s))
            screenImage = screenImage.cropped(to: CGRect(x: 0, y: 0,
                                                         width: CGFloat(outputWidth),
                                                         height: CGFloat(outputHeight)))
        }

        if includeWebcam, let camera = currentCameraImage(outputWidth: outputWidth,
                                                          outputHeight: outputHeight) {
            screenImage = camera.composited(over: screenImage)
        }

        if includeClicks, options.drawClickRipples, let tracker = clickTracker {
            let now = CACurrentMediaTime()
            let recent = tracker.recentEvents(now: now)
            if !recent.isEmpty {
                let ripples = renderRipples(events: recent,
                                            now: now,
                                            outputWidth: outputWidth,
                                            outputHeight: outputHeight)
                if let ripples {
                    screenImage = ripples.composited(over: screenImage)
                }
            }
        }

        guard let pool = ensurePool(width: outputWidth, height: outputHeight) else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let outBuffer = pixelBuffer else { return nil }

        context.render(screenImage, to: outBuffer)

        var timing = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(screenSampleBuffer, at: 0, timingInfoOut: &timing)

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: outBuffer,
                                                     formatDescriptionOut: &formatDescription)

        var newSample: CMSampleBuffer?
        guard let formatDescription else { return nil }
        let result = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                        imageBuffer: outBuffer,
                                                        dataReady: true,
                                                        makeDataReadyCallback: nil,
                                                        refcon: nil,
                                                        formatDescription: formatDescription,
                                                        sampleTiming: &timing,
                                                        sampleBufferOut: &newSample)
        if result != noErr { return nil }
        return newSample
    }

    private func hasCameraFrame() -> Bool {
        cameraLock.lock()
        defer { cameraLock.unlock() }
        return latestCameraBuffer != nil
    }

    private func currentCameraImage(outputWidth: Int, outputHeight: Int) -> CIImage? {
        cameraLock.lock()
        let buffer = latestCameraBuffer
        cameraLock.unlock()
        guard let buffer else { return nil }

        var image = CIImage(cvPixelBuffer: buffer)
        let camW = CGFloat(CVPixelBufferGetWidth(buffer))
        let camH = CGFloat(CVPixelBufferGetHeight(buffer))

        let targetH = CGFloat(outputHeight) * options.webcamRelativeHeight
        let scale = targetH / camH
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        image = image.transformed(by: CGAffineTransform(translationX: camW * scale, y: 0))

        let scaledW = camW * scale
        let scaledH = targetH

        let margin = options.webcamMargin
        let originX: CGFloat
        let originY: CGFloat
        switch options.webcamCorner {
        case .topLeft:
            originX = margin
            originY = CGFloat(outputHeight) - scaledH - margin
        case .topRight:
            originX = CGFloat(outputWidth) - scaledW - margin
            originY = CGFloat(outputHeight) - scaledH - margin
        case .bottomLeft:
            originX = margin
            originY = margin
        case .bottomRight:
            originX = CGFloat(outputWidth) - scaledW - margin
            originY = margin
        }

        image = image.transformed(by: CGAffineTransform(translationX: originX, y: originY))

        let cornerRadius = min(scaledW, scaledH) * 0.12
        let rounded = CIFilter.roundedRectangleGenerator()
        rounded.extent = CGRect(x: originX, y: originY, width: scaledW, height: scaledH)
        rounded.radius = Float(cornerRadius)
        rounded.color = CIColor.white
        if let mask = rounded.outputImage {
            let blender = CIFilter.blendWithMask()
            blender.inputImage = image
            blender.maskImage = mask
            blender.backgroundImage = CIImage(color: CIColor.clear).cropped(to: image.extent)
            if let blended = blender.outputImage {
                return blended
            }
        }
        return image
    }

    private func renderRipples(events: [ClickEvent],
                               now: TimeInterval,
                               outputWidth: Int,
                               outputHeight: Int) -> CIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let cg = CGContext(data: nil,
                                 width: outputWidth,
                                 height: outputHeight,
                                 bitsPerComponent: 8,
                                 bytesPerRow: outputWidth * 4,
                                 space: colorSpace,
                                 bitmapInfo: bitmapInfo) else {
            return nil
        }
        cg.clear(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

        let source = options.sourceFrameInGlobalCoords
        for click in events {
            let age = now - click.timestamp
            let life: CGFloat = 0.6
            guard age <= life else { continue }
            let t = CGFloat(age) / life

            let global = click.globalPoint
            if !source.isEmpty, !source.contains(global) { continue }

            let xRel = source.isEmpty
                ? 0.5
                : (global.x - source.minX) / max(1, source.width)
            let yRel = source.isEmpty
                ? 0.5
                : 1.0 - ((global.y - source.minY) / max(1, source.height))
            let x = xRel * CGFloat(outputWidth)
            let y = yRel * CGFloat(outputHeight)

            let baseRadius: CGFloat = CGFloat(min(outputWidth, outputHeight)) * 0.06
            let radius = baseRadius * (0.4 + t)
            let alpha: CGFloat = (1 - t) * 0.85

            let r: CGFloat
            let g: CGFloat
            let b: CGFloat
            if click.isRight {
                r = 1.0; g = 0.6; b = 0.2
            } else {
                r = 0.2; g = 0.5; b = 1.0
            }
            cg.setStrokeColor(red: r, green: g, blue: b, alpha: alpha)
            cg.setLineWidth(max(2, baseRadius * 0.18))
            cg.strokeEllipse(in: CGRect(x: x - radius,
                                        y: y - radius,
                                        width: radius * 2,
                                        height: radius * 2))
        }

        guard let cgImage = cg.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    private func ensurePool(width: Int, height: Int) -> CVPixelBufferPool? {
        if let pool, poolWidth == width, poolHeight == height { return pool }

        let poolAttrs = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var newPool: CVPixelBufferPool?
        let result = CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                             poolAttrs as CFDictionary,
                                             pixelBufferAttrs as CFDictionary,
                                             &newPool)
        guard result == kCVReturnSuccess else { return nil }
        self.pool = newPool
        self.poolWidth = width
        self.poolHeight = height
        return newPool
    }
}
