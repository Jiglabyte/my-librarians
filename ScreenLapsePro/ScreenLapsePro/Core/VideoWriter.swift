// ScreenLapsePro
// Core/VideoWriter.swift
// AVAssetWriter wrapper: HEVC video + optional AAC audio tracks

import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox

// MARK: - VideoWriter

final class VideoWriter {

    let outputURL: URL

    private let assetWriter: AVAssetWriter
    private let vwInput:     AVAssetWriterInput

    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput:    AVAssetWriterInput?

    private let isTimeLapse:          Bool
    private let timeLapseMultiplier:  Int
    private var frameIndex:           Int64 = 0

    // MARK: Init

    init(outputURL: URL,
         width: Int,
         height: Int,
         isTimeLapse: Bool,
         timeLapseMultiplier: Int,
         bitratePreset: BitratePreset = .medium,
         includeSystemAudio: Bool = false,
         includeMicAudio: Bool = false) throws {

        self.outputURL           = outputURL
        self.isTimeLapse         = isTimeLapse
        self.timeLapseMultiplier = timeLapseMultiplier

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // MARK: Video input

        let pixelCount    = width * height
        let scaledBitrate = bitratePreset.bitrate(forPixelCount: pixelCount)
        let codec: AVVideoCodecType = Prefs.useHEVC ? .hevc : .h264

        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey:          scaledBitrate,
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey:     60,
        ]
        if Prefs.useHEVC {
            compressionProps[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey:                 codec,
            AVVideoWidthKey:                 width,
            AVVideoHeightKey:                height,
            AVVideoCompressionPropertiesKey: compressionProps,
        ]

        vwInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vwInput.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(vwInput) else {
            throw VideoWriterError.cannotAddInput
        }
        assetWriter.add(vwInput)

        // MARK: Audio inputs

        let audioSettings: [String: Any] = [
            AVFormatIDKey:            kAudioFormatMPEG4AAC,
            AVSampleRateKey:          48000,
            AVNumberOfChannelsKey:    2,
            AVEncoderBitRateKey:      192_000,
        ]

        if includeSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                systemAudioInput = input
            }
        }

        if includeMicAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                micAudioInput = input
            }
        }
    }

    // MARK: Lifecycle

    func start() {
        guard assetWriter.status == .unknown else { return }
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
    }

    // MARK: Append — Video

    func appendFrame(_ sampleBuffer: CMSampleBuffer) {
        guard vwInput.isReadyForMoreMediaData else { return }
        guard assetWriter.status == .writing  else { return }

        if isTimeLapse {
            let syntheticPTS = CMTime(value: frameIndex, timescale: 30)
            frameIndex += 1

            var timingInfo = CMSampleTimingInfo(
                duration:              CMTime(value: 1, timescale: 30),
                presentationTimeStamp: syntheticPTS,
                decodeTimeStamp:       .invalid
            )
            var remapped: CMSampleBuffer?
            let status = CMSampleBufferCreateCopyWithNewTiming(
                allocator:              kCFAllocatorDefault,
                sampleBuffer:           sampleBuffer,
                sampleTimingEntryCount: 1,
                sampleTimingArray:      &timingInfo,
                sampleBufferOut:        &remapped
            )
            if status == noErr, let buf = remapped {
                vwInput.append(buf)
            }
        } else {
            vwInput.append(sampleBuffer)
        }
    }

    // MARK: Append — Audio

    func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let input = systemAudioInput,
              input.isReadyForMoreMediaData,
              assetWriter.status == .writing else { return }
        input.append(sampleBuffer)
    }

    func appendMicAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let input = micAudioInput,
              input.isReadyForMoreMediaData,
              assetWriter.status == .writing else { return }
        input.append(sampleBuffer)
    }

    // MARK: Finish

    @discardableResult
    func finish() async -> URL {
        vwInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        micAudioInput?.markAsFinished()
        await assetWriter.finishWriting()
        return outputURL
    }

    // MARK: Errors

    enum VideoWriterError: LocalizedError {
        case cannotAddInput

        var errorDescription: String? {
            "AVAssetWriter could not add the video input track."
        }
    }
}
