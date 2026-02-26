import Foundation
import ReplayKit
import AVFoundation
import CoreMedia
import AudioToolbox

/// Broadcast Upload Extension: 仅捕获系统播放音频，不录制/保存视频。
/// 将系统格式（多为 48kHz Float32）转换为 16kHz 单声道 Int16 再写入，供主 App 语音识别使用。
class AudioCaptureExtension: RPBroadcastSampleHandler {

    private let appGroupIdentifier = "group.com.doublesubtitle.app"
    private let broadcastActiveKey = "isBroadcastActive"
    /// 用文件表示广播已开始，避免 Extension 内 UserDefaults(suiteName:) 触发 CFPrefs 导致主 App 读不到
    private let broadcastActiveFileName = "broadcast_active"

    /// 主 App 读取的格式 key（Extension 写 raw 时写入，主 App 据此做采样率转换）
    static let audioFormatSampleRateKey = "audioFormatSampleRate"
    static let audioFormatChannelsKey = "audioFormatChannels"
    static let audioFormatFloatKey = "audioFormatFloat"
    static let audioFormatInterleavedKey = "audioFormatInterleaved"

    private static let targetSampleRate: Double = 16000
    private static let targetChannels: AVAudioChannelCount = 1
    static let audioFormatBitsPerChannelKey = "audioFormatBitsPerChannel"

    private var asbdLoggedOnce = false

    // Debug: 直接 dump CMBlockBuffer 原始字节（零解析），用于验证系统捕获的数据
    private var debugDumpFileHandle: FileHandle?
    private var debugDumpBytesWritten: UInt64 = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        print("[AudioCaptureExtension] Broadcast started with setup info: \(setupInfo ?? [:])")
        setBroadcastActive(true)
    }

    override func broadcastFinished() {
        print("[AudioCaptureExtension] Broadcast finished")
        closeDebugDumpFile()
        setBroadcastActive(false)
    }

    /// 通过 App Group 容器内文件通知主 App 广播状态，避免 UserDefaults 在 Extension 内 CFPrefs 异常导致主 App 读不到
    private func setBroadcastActive(_ active: Bool) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return }
        let flagURL = containerURL.appendingPathComponent(broadcastActiveFileName)
        if active {
            try? Data().write(to: flagURL)
        } else {
            try? FileManager.default.removeItem(at: flagURL)
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        if sampleBufferType != .audioApp { return }

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            print("[AudioCaptureExtension] No format description")
            return
        }
        let asbd = asbdPtr.pointee

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("[AudioCaptureExtension] No block buffer")
            return
        }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let data = dataPointer, length > 0 else {
            print("[AudioCaptureExtension] No data pointer or length=0")
            return
        }

        if !asbdLoggedOnce {
            asbdLoggedOnce = true
            let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
            let isPacked = (asbd.mFormatFlags & kAudioFormatFlagIsPacked) != 0
            let isSigned = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
            print("[AudioCaptureExtension] ASBD: sampleRate=\(asbd.mSampleRate) channels=\(asbd.mChannelsPerFrame) bitsPerChannel=\(asbd.mBitsPerChannel) bytesPerFrame=\(asbd.mBytesPerFrame) bytesPerPacket=\(asbd.mBytesPerPacket) formatFlags=0x\(String(asbd.mFormatFlags, radix: 16)) isFloat=\(isFloat) isNonInterleaved=\(isNonInterleaved) isPacked=\(isPacked) isSigned=\(isSigned)")
        }

        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        let bytesPerFrame = Int(asbd.mBytesPerFrame)
        let totalBytesPerFrame: Int
        if isNonInterleaved {
            totalBytesPerFrame = bytesPerFrame * Int(asbd.mChannelsPerFrame)
        } else {
            totalBytesPerFrame = bytesPerFrame
        }
        let frameCount = length / totalBytesPerFrame
        guard frameCount > 0 else { return }

        // 直接 dump 原始字节到文件（零格式解析）
        appendToDebugDumpFile(data: data, length: length, asbd: asbd)

        let dataToWrite: Data
        let needSampleRateConversion = abs(Double(asbd.mSampleRate) - Self.targetSampleRate) > 1
        if needSampleRateConversion {
            writeRawFormatToUserDefaults(asbd: asbd)
            dataToWrite = Data(bytes: data, count: length)
        } else if let pcm16kData = convertTo16kMonoInt16(source: data, sourceLength: length, asbd: asbd, frameCount: frameCount) {
            dataToWrite = pcm16kData
        } else {
            writeRawFormatToUserDefaults(asbd: asbd)
            dataToWrite = Data(bytes: data, count: length)
        }
        writeAudioDataToSharedContainer(dataToWrite)
    }

    /// 将 ASBD 描述的 PCM 转为 16kHz 单声道 Int16。支持 Float32/Int16、任意采样率与声道数。
    private func convertTo16kMonoInt16(source: UnsafeMutablePointer<Int8>, sourceLength: Int, asbd: AudioStreamBasicDescription, frameCount: Int) -> Data? {
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let sampleRate = asbd.mSampleRate
        let channels = Int(asbd.mChannelsPerFrame)

        // 已是 16kHz 单声道 Int16 则直接拷贝（仅取第一声道）
        if abs(sampleRate - Self.targetSampleRate) < 1 && channels == 1 && !isFloat && asbd.mBitsPerChannel == 16 {
            return Data(bytes: source, count: sourceLength)
        }

        guard let sourceFormat = createSourceFormat(asbd: asbd) else {
            print("[AudioCaptureExtension] createSourceFormat failed (rate=\(sampleRate) ch=\(channels) float=\(isFloat))")
            return nil
        }
        guard let destFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.targetSampleRate, channels: Self.targetChannels, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: destFormat) else {
            print("[AudioCaptureExtension] Failed to create destFormat or converter")
            return nil
        }

        guard let srcBuffer = createSourcePCMBuffer(data: source, length: sourceLength, asbd: asbd, frameCount: frameCount, isFloat: isFloat, channels: channels) else {
            print("[AudioCaptureExtension] createSourcePCMBuffer failed")
            return nil
        }

        // AVAudioConverter 要求 outputBuffer.frameCapacity >= inputBuffer.frameLength，否则崩溃
        let ratio = Self.targetSampleRate / sampleRate
        let estimatedOutFrames = AVAudioFrameCount(Double(frameCount) * ratio) + 1
        let inputFrames = AVAudioFrameCount(frameCount)
        let outFrameCapacity = max(estimatedOutFrames, inputFrames)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: destFormat, frameCapacity: outFrameCapacity) else {
            return nil
        }

        // 使用 block-based API 以支持采样率转换（简单 convert(to:from:) 不支持 SRC）
        var inputProvided = false
        var convertError: NSError?
        let convertStatus = converter.convert(to: outBuffer, error: &convertError) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return srcBuffer
        }
        if let convertError = convertError {
            print("[AudioCaptureExtension] Convert error: \(convertError.localizedDescription)")
            return nil
        }
        if convertStatus == .error {
            print("[AudioCaptureExtension] Convert status=error")
            return nil
        }
        if outBuffer.frameLength == 0 {
            return nil
        }

        let outFrames = Int(outBuffer.frameLength)
        guard outFrames > 0, let channelData = outBuffer.int16ChannelData else { return nil }
        return Data(bytes: channelData[0], count: outFrames * 2)
    }

    private func createSourceFormat(asbd: AudioStreamBasicDescription) -> AVAudioFormat? {
        // 优先用 ASBD 创建；若失败则用数值手动构建（兼容 ReplayKit 的 ASBD）
        var copy = asbd
        if let fmt = withUnsafePointer(to: &copy, { AVAudioFormat(streamDescription: $0) }) {
            return fmt
        }
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let channels = AVAudioChannelCount(asbd.mChannelsPerFrame)
        let sampleRate = asbd.mSampleRate
        if isFloat {
            return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0)
        } else if asbd.mBitsPerChannel == 16 {
            return AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0)
        }
        return nil
    }

    private func createSourcePCMBuffer(data: UnsafeMutablePointer<Int8>, length: Int, asbd: AudioStreamBasicDescription, frameCount: Int, isFloat: Bool, channels: Int) -> AVAudioPCMBuffer? {
        guard let format = createSourceFormat(asbd: asbd),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let bytesPerFrame = Int(asbd.mBytesPerFrame)
        let bytesPerChannelPerFrame = bytesPerFrame / channels
        let isPlanar = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        if isPlanar {
            let bytesPerChannel = length / channels
            if isFloat, let dst = buffer.floatChannelData {
                for ch in 0..<channels { memcpy(dst[ch], data.advanced(by: ch * bytesPerChannel), bytesPerChannel) }
            } else if let dst = buffer.int16ChannelData {
                for ch in 0..<channels { memcpy(dst[ch], data.advanced(by: ch * bytesPerChannel), bytesPerChannel) }
            } else { return nil }
        } else {
            // Interleaved: 逐帧拷贝到 planar
            if isFloat, let dst = buffer.floatChannelData {
                for frame in 0..<frameCount {
                    let srcOffset = frame * bytesPerFrame
                    for ch in 0..<channels {
                        memcpy(dst[ch].advanced(by: frame), data.advanced(by: srcOffset + ch * bytesPerChannelPerFrame), bytesPerChannelPerFrame)
                    }
                }
            } else if let dst = buffer.int16ChannelData {
                for frame in 0..<frameCount {
                    let srcOffset = frame * bytesPerFrame
                    for ch in 0..<channels {
                        memcpy(dst[ch].advanced(by: frame), data.advanced(by: srcOffset + ch * bytesPerChannelPerFrame), bytesPerChannelPerFrame)
                    }
                }
            } else { return nil }
        }
        return buffer
    }

    private func writeRawFormatToUserDefaults(asbd: AudioStreamBasicDescription) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return }
        let formatURL = containerURL.appendingPathComponent("audio_format.plist")
        let dict: [String: Any] = [
            Self.audioFormatSampleRateKey: asbd.mSampleRate,
            Self.audioFormatChannelsKey: Int(asbd.mChannelsPerFrame),
            Self.audioFormatFloatKey: (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0,
            Self.audioFormatInterleavedKey: (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
            Self.audioFormatBitsPerChannelKey: Int(asbd.mBitsPerChannel)
        ]
        try? (dict as NSDictionary).write(to: formatURL)
    }

    // MARK: - Debug: 直接 dump CMBlockBuffer 原始字节到文件（零格式解析）

    private func appendToDebugDumpFile(data: UnsafeMutablePointer<Int8>, length: Int, asbd: AudioStreamBasicDescription) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return }

        if debugDumpFileHandle == nil {
            let dumpURL = containerURL.appendingPathComponent("debug_raw_dump.bin")
            try? FileManager.default.removeItem(at: dumpURL)
            FileManager.default.createFile(atPath: dumpURL.path, contents: nil)
            debugDumpFileHandle = try? FileHandle(forWritingTo: dumpURL)
            debugDumpBytesWritten = 0

            // 同时写一份 ASBD 文本描述，方便用 ffplay/Audacity 打开 raw
            let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
            let info = """
            sampleRate=\(asbd.mSampleRate)
            channels=\(asbd.mChannelsPerFrame)
            bitsPerChannel=\(asbd.mBitsPerChannel)
            bytesPerFrame=\(asbd.mBytesPerFrame)
            formatFlags=0x\(String(asbd.mFormatFlags, radix: 16))
            isFloat=\(isFloat)
            isNonInterleaved=\(isNonInterleaved)

            播放命令(interleaved):
            ffplay -f \(isFloat ? "f32le" : "s16le") -ar \(Int(asbd.mSampleRate)) -ac \(asbd.mChannelsPerFrame) debug_raw_dump.bin

            如果是 non-interleaved(planar)，需要先用脚本交织再播放。
            """
            let infoURL = containerURL.appendingPathComponent("debug_raw_format.txt")
            try? info.write(to: infoURL, atomically: true, encoding: .utf8)
            print("[AudioCaptureExtension] Debug dump started: \(dumpURL.path)")
        }

        guard let handle = debugDumpFileHandle else { return }
        let rawData = Data(bytes: data, count: length)
        handle.write(rawData)
        debugDumpBytesWritten += UInt64(length)
    }

    private func closeDebugDumpFile() {
        guard let handle = debugDumpFileHandle else { return }
        try? handle.close()
        debugDumpFileHandle = nil
        print("[AudioCaptureExtension] Debug dump closed, total bytes=\(debugDumpBytesWritten)")
    }

    private func writeAudioDataToSharedContainer(_ data: Data) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            print("[AudioCaptureExtension] No App Group container URL")
            return
        }
        let audioFileURL = containerURL.appendingPathComponent("captured_audio.pcm")
        do {
            if FileManager.default.fileExists(atPath: audioFileURL.path) {
                let fileHandle = try FileHandle(forWritingTo: audioFileURL)
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try fileHandle.close()
            } else {
                try data.write(to: audioFileURL)
            }
        } catch {
            print("[AudioCaptureExtension] Failed to write: \(error.localizedDescription)")
        }
    }
}
