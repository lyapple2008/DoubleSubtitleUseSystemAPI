import Foundation
import ReplayKit
import AVFoundation
import CoreMedia
import AudioToolbox

/// Broadcast Upload Extension: 仅捕获系统播放音频，不录制/保存视频。
class AudioCaptureExtension: RPBroadcastSampleHandler {

    private let appGroupIdentifier = "group.com.doublesubtitle.app"
    private let broadcastActiveKey = "isBroadcastActive"

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        print("[AudioCaptureExtension] Broadcast started with setup info: \(setupInfo ?? [:])")
        UserDefaults(suiteName: appGroupIdentifier)?.set(true, forKey: broadcastActiveKey)
    }

    override func broadcastFinished() {
        print("[AudioCaptureExtension] Broadcast finished")
        UserDefaults(suiteName: appGroupIdentifier)?.set(false, forKey: broadcastActiveKey)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // 仅处理应用内音频，不处理、不写入任何视频。开始/结束完全由用户通过 RPSystemBroadcastPickerView 控制。
        if sampleBufferType == .audioApp {
            // Get audio format information
            if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
                if let asbd = asbd {
                    print("[AudioCaptureExtension] Audio format - SampleRate: \(asbd.mSampleRate), Channels: \(asbd.mChannelsPerFrame), BitsPerChannel: \(asbd.mBitsPerChannel)")
                }
            }

            // Get the audio data from the sample buffer
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                print("[AudioCaptureExtension] Failed to get block buffer")
                return
            }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            guard status == kCMBlockBufferNoErr, let data = dataPointer else {
                print("[AudioCaptureExtension] Failed to get data pointer, status: \(status)")
                return
            }

            // Convert to Data
            let audioData = Data(bytes: data, count: length)

            // Write audio data to App Group container
            writeAudioDataToSharedContainer(audioData)

            print("[AudioCaptureExtension] Received app audio buffer, size: \(length) bytes")
        }
        // 忽略视频类型：.video、.audioMic 等，仅需 .audioApp（系统播放音频），不写入任何视频文件
    }

    private func writeAudioDataToSharedContainer(_ data: Data) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            print("[AudioCaptureExtension] Failed to get App Group container URL")
            return
        }

        let audioFileURL = containerURL.appendingPathComponent("captured_audio.pcm")

        // Append audio data to file
        do {
            if FileManager.default.fileExists(atPath: audioFileURL.path) {
                let fileHandle = try FileHandle(forWritingTo: audioFileURL)
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try fileHandle.close()
            } else {
                try data.write(to: audioFileURL)
            }
            print("[AudioCaptureExtension] Wrote \(data.count) bytes to shared container")
        } catch {
            print("[AudioCaptureExtension] Failed to write audio data: \(error)")
        }
    }
}
