import SwiftUI
import ReplayKit
import AVFoundation
import UIKit

/// Protocol for receiving audio capture events
protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureDidStart()
    func audioCaptureDidStop()
    func audioCaptureDidReceiveAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func audioCaptureDidFail(with error: Error)
}

/// SwiftUI wrapper for RPSystemBroadcastPickerView. When `trigger` becomes true, programmatically shows the system broadcast picker.
struct BroadcastPickerView: UIViewRepresentable {
    var preferredExtension: String?
    @Binding var trigger: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(binding: $trigger)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let picker = RPSystemBroadcastPickerView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.preferredExtension = preferredExtension
        picker.showsMicrophoneButton = false
        container.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            picker.topAnchor.constraint(equalTo: container.topAnchor),
            picker.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard trigger else { return }
        for subview in uiView.subviews {
            if let picker = subview as? RPSystemBroadcastPickerView {
                if let ext = preferredExtension {
                    picker.preferredExtension = ext
                }
                picker.showsMicrophoneButton = false
                let coordinator = context.coordinator
                DispatchQueue.main.async {
                    Self.triggerPickerButton(in: picker)
                    coordinator.binding.wrappedValue = false
                }
                return
            }
        }
    }

    final class Coordinator {
        var binding: Binding<Bool>
        init(binding: Binding<Bool>) {
            self.binding = binding
        }
    }

    private static func triggerPickerButton(in picker: RPSystemBroadcastPickerView) {
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .touchUpInside)
                return
            }
        }
    }
}

/// Container view for broadcast picker with instructions
struct BroadcastPickerContainerView: View {
    var preferredExtension: String?
    var onDismiss: (() -> Void)?
    @State private var pickerTapped = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss?()
                }

            VStack(spacing: 20) {
                Text("点击下方按钮，在系统弹窗中选择「双语字幕」并点击「开始直播」")
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // Broadcast picker - triggers system RPSystemBroadcastPickerView
                BroadcastPickerView(preferredExtension: preferredExtension, trigger: .constant(false))
                    .frame(width: 80, height: 80)
                    .background(Color.white)
                    .cornerRadius(40)

                Text("仅当您点击「开始直播」后才会开始捕获音频")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button("取消") {
                    onDismiss?()
                }
                .foregroundColor(.white)
                .padding(.top, 20)
            }
            .padding(30)
            .background(Color(.systemGray5))
            .cornerRadius(16)
        }
    }
}

/// Modified AudioCaptureManager that doesn't require UIView embedding
final class AudioCaptureManager: NSObject {
    static let shared = AudioCaptureManager()

    private let logTag = "AudioCaptureManager"
    weak var delegate: AudioCaptureDelegate?

    private let appGroupIdentifier = "group.com.doublesubtitle.app"
    private let broadcastActiveKey = "isBroadcastActive"
    /// Extension 通过该文件通知广播已开始，避免 UserDefaults 在 Extension 内异常导致主 App 读不到
    private let broadcastActiveFileName = "broadcast_active"
    /// Extension 写 raw 时写入的格式 key，主 App 据此做采样率/声道转换
    private let audioFormatSampleRateKey = "audioFormatSampleRate"
    private let audioFormatChannelsKey = "audioFormatChannels"
    private let audioFormatFloatKey = "audioFormatFloat"
    private let audioFormatInterleavedKey = "audioFormatInterleaved"
    private let audioFormatBitsPerChannelKey = "audioFormatBitsPerChannel"
    private var isRecording = false
    private var fileMonitorTimer: Timer?
    private var broadcastStartPollTimer: Timer?
    private var lastReadPosition: UInt64 = 0
    private var broadcastPicker: RPSystemBroadcastPickerView?

    // MARK: - Debug: 保存送识别前的音频到 WAV 文件
    private var debugAudioFileHandle: FileHandle?
    private var debugAudioDataLength: UInt32 = 0
    private let debugAudioSampleRate: UInt32 = 16000
    private let debugAudioChannels: UInt16 = 1
    private let debugAudioBitsPerSample: UInt16 = 16

    private override init() {
        super.init()
        setupAudioSession()
    }

    // MARK: - Public Methods

    /// Check if screen recording is available
    var isAvailable: Bool {
        return true
    }

    /// Check if currently recording
    var isCapturing: Bool {
        isRecording
    }

    /// Start waiting for user to start broadcast. Call when RPSystemBroadcastPickerView is visible; actual capture starts when user taps "开始直播" in system UI.
    func startWaitingForBroadcastStart() {
        guard isAvailable else { return }
        guard !isRecording else { return }
        if broadcastStartPollTimer != nil { return }
        print("[AudioCaptureManager] Waiting for user to tap 开始直播 in system picker")
        startBroadcastStartPolling()
    }

    /// Cancel waiting for user to start broadcast.
    func cancelPendingCapture() {
        stopBroadcastStartPolling()
    }

    /// Stop audio capture (local cleanup only). Extension 的开始/结束完全由用户通过 RPSystemBroadcastPickerView 控制。
    func stopCapture() {
        guard isRecording else { return }

        print("[AudioCaptureManager] Stopping capture")

        finalizeDebugAudioFile()

        // Stop file monitoring
        stopFileMonitoring()

        // Clear the audio file
        clearSharedAudioFile()

        isRecording = false

        DispatchQueue.main.async {
            self.delegate?.audioCaptureDidStop()
        }
    }

    // MARK: - Private Methods

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("[AudioCaptureManager] Failed to setup audio session: \(error)")
        }
    }

    private func startBroadcastStartPolling() {
        stopBroadcastStartPolling()
        broadcastStartPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkBroadcastStarted()
        }
        RunLoop.main.add(broadcastStartPollTimer!, forMode: .common)
    }

    private func stopBroadcastStartPolling() {
        broadcastStartPollTimer?.invalidate()
        broadcastStartPollTimer = nil
    }

    private func checkBroadcastStarted() {
        // 通过 App Group 容器内标记文件判断（Extension 内 UserDefaults 可能因 CFPrefs 异常不可用）
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return }
        let flagURL = containerURL.appendingPathComponent(broadcastActiveFileName)
        guard FileManager.default.fileExists(atPath: flagURL.path) else { return }
        stopBroadcastStartPolling()
        isRecording = true
        startFileMonitoring()
        delegate?.audioCaptureDidStart()
        print("[AudioCaptureManager] User started broadcast, capture and file monitoring started")
    }

    private func startFileMonitoring() {
        print("[AudioCaptureManager] Starting file monitoring")

        // Reset read position
        lastReadPosition = 0

        // Clear previous audio file
        clearSharedAudioFile()

        startDebugAudioFile()

        // Start monitoring the shared audio file (add to common run loop mode so it fires during UI interaction)
        fileMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkForNewAudioData()
        }
        RunLoop.main.add(fileMonitorTimer!, forMode: .common)
    }

    private func stopFileMonitoring() {
        print("[AudioCaptureManager] Stopping file monitoring")
        fileMonitorTimer?.invalidate()
        fileMonitorTimer = nil
    }

    private func checkForNewAudioData() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }

        let audioFileURL = containerURL.appendingPathComponent("captured_audio.pcm")

        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            return
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioFileURL.path)
            let fileSize = attributes[.size] as? UInt64 ?? 0

            guard fileSize > lastReadPosition else {
                return
            }

            // Read new audio data
            let handle = try FileHandle(forReadingFrom: audioFileURL)
            handle.seek(toFileOffset: lastReadPosition)

            let data = handle.readDataToEndOfFile()
            try handle.close()

            lastReadPosition = fileSize

            if !data.isEmpty, let pcmBuffer = createPCMBufferForRecognition(from: data) {
                print("[\(logTag)] Read audio size=\(data.count) bytes, PCM frameLength=\(pcmBuffer.frameLength)")
                appendToDebugAudioFile(pcmBuffer)
                let delegate = self.delegate
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if delegate == nil {
                        print("[\(self.logTag)] WARNING: delegate is nil, buffer not delivered to speech recognition")
                    } else {
                        delegate?.audioCaptureDidReceiveAudioBuffer(pcmBuffer)
                        print("[\(self.logTag)] Delivered buffer to delegate frameLength=\(pcmBuffer.frameLength)")
                    }
                }
            }
        } catch {
            print("[AudioCaptureManager] Error reading audio file: \(error)")
        }
    }

    private func clearSharedAudioFile() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }

        let audioFileURL = containerURL.appendingPathComponent("captured_audio.pcm")

        try? FileManager.default.removeItem(at: audioFileURL)
        print("[AudioCaptureManager] Cleared shared audio file")
    }

    // MARK: - Debug Audio File (WAV)

    private func startDebugAudioFile() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let wavURL = docs.appendingPathComponent("debug_recognition_audio.wav")
        try? FileManager.default.removeItem(at: wavURL)
        FileManager.default.createFile(atPath: wavURL.path, contents: nil)
        debugAudioFileHandle = try? FileHandle(forWritingTo: wavURL)
        debugAudioDataLength = 0
        // 先写 44 字节占位 WAV 头，停止时回填
        let placeholder = Data(count: 44)
        debugAudioFileHandle?.write(placeholder)
        print("[\(logTag)] Debug audio file created: \(wavURL.path)")
    }

    private func appendToDebugAudioFile(_ buffer: AVAudioPCMBuffer) {
        guard let handle = debugAudioFileHandle else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let format = buffer.format
        if format.commonFormat == .pcmFormatInt16, let ch = buffer.int16ChannelData {
            let byteCount = frames * 2
            let data = Data(bytes: ch[0], count: byteCount)
            handle.write(data)
            debugAudioDataLength += UInt32(byteCount)
        } else if format.commonFormat == .pcmFormatFloat32, let ch = buffer.floatChannelData {
            // Float32 → Int16 再写入 WAV
            var int16Buf = [Int16](repeating: 0, count: frames)
            for i in 0..<frames {
                let clamped = max(-1.0, min(1.0, ch[0][i]))
                int16Buf[i] = Int16(clamped * 32767)
            }
            let data = Data(bytes: &int16Buf, count: frames * 2)
            handle.write(data)
            debugAudioDataLength += UInt32(frames * 2)
        }
    }

    private func finalizeDebugAudioFile() {
        guard let handle = debugAudioFileHandle else { return }
        let sampleRate = debugAudioSampleRate
        let channels = debugAudioChannels
        let bitsPerSample = debugAudioBitsPerSample
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = debugAudioDataLength
        let fileSize = 36 + dataSize

        var header = Data(count: 44)
        header.replaceSubrange(0..<4, with: "RIFF".data(using: .ascii)!)
        header.replaceSubrange(4..<8, with: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.replaceSubrange(8..<12, with: "WAVE".data(using: .ascii)!)
        header.replaceSubrange(12..<16, with: "fmt ".data(using: .ascii)!)
        header.replaceSubrange(16..<20, with: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.replaceSubrange(20..<22, with: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.replaceSubrange(22..<24, with: withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.replaceSubrange(24..<28, with: withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.replaceSubrange(28..<32, with: withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.replaceSubrange(32..<34, with: withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.replaceSubrange(34..<36, with: withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.replaceSubrange(36..<40, with: "data".data(using: .ascii)!)
        header.replaceSubrange(40..<44, with: withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        handle.seek(toFileOffset: 0)
        handle.write(header)
        try? handle.close()
        debugAudioFileHandle = nil

        let totalSeconds = Double(dataSize) / Double(byteRate)
        print("[\(logTag)] Debug audio file finalized: \(dataSize) bytes, \(String(format: "%.1f", totalSeconds))s")
    }

    private var plistLoggedOnce = false

    /// 从 App Group 容器内 audio_format.plist 读取格式（Extension 写 raw 时写入），避免依赖 UserDefaults
    private func readRawAudioFormatFromContainer() -> (sampleRate: Double, channels: Int, isFloat: Bool, interleaved: Bool, bitsPerChannel: Int) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return (0, 0, false, false, 0)
        }
        let formatURL = containerURL.appendingPathComponent("audio_format.plist")
        guard let dict = NSDictionary(contentsOf: formatURL) as? [String: Any] else {
            return (0, 0, false, false, 0)
        }
        let sampleRate = (dict[audioFormatSampleRateKey] as? NSNumber)?.doubleValue ?? 0
        let channels = (dict[audioFormatChannelsKey] as? NSNumber)?.intValue ?? 0
        var isFloat = (dict[audioFormatFloatKey] as? NSNumber)?.boolValue ?? false
        let interleaved = (dict[audioFormatInterleavedKey] as? NSNumber)?.boolValue ?? false
        let bitsPerChannel = (dict[audioFormatBitsPerChannelKey] as? NSNumber)?.intValue ?? (isFloat ? 32 : 16)

        // 安全校验：如果 bitsPerChannel=32 且 isFloat=false，很可能实际是 Float32（ReplayKit 常见格式）
        if bitsPerChannel == 32 && !isFloat {
            print("[\(logTag)] WARNING: bitsPerChannel=32 but isFloat=false, treating as Float32")
            isFloat = true
        }

        if !plistLoggedOnce {
            plistLoggedOnce = true
            print("[\(logTag)] plist values: sampleRate=\(sampleRate) channels=\(channels) isFloat=\(isFloat) interleaved=\(interleaved) bitsPerChannel=\(bitsPerChannel)")
        }
        return (sampleRate, Int(channels), isFloat, interleaved, bitsPerChannel)
    }

    private var convertLogCount = 0

    /// 根据 Extension 写入的格式将 raw 转为语音识别所需格式。
    /// 使用 AVAudioConverter 的 block-based API（convert(to:error:withInputFrom:)）进行转换，
    /// 因为简单的 convert(to:from:) 不支持采样率转换（会报 -50）。
    private func createPCMBufferForRecognition(from data: Data) -> AVAudioPCMBuffer? {
        let (sampleRate, channels, isFloat, interleaved, _) = readRawAudioFormatFromContainer()

        let destFormat = SpeechRecognitionManager.shared.preferredRecognitionFormat

        if sampleRate <= 0 {
            return createPCMBufferFromRaw(data, destFormat: destFormat)
        }
        // AVAudioPCMBuffer 的 int16ChannelData/floatChannelData 只对 non-interleaved 正常工作：
        // interleaved 格式只有 1 个 buffer（所有声道交错），channelData[ch>0] 越界。
        // 因此始终创建 non-interleaved 的源格式；interleaved 标志仅告知 createSourcePCMBuffer 如何解读 raw 布局。
        let srcFormat = AVAudioFormat(
            commonFormat: isFloat ? .pcmFormatFloat32 : .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        )
        guard let srcFormat = srcFormat else {
            return createPCMBufferFromRaw(data, destFormat: destFormat)
        }

        let dest = destFormat ?? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        if convertLogCount < 3 {
            print("[\(logTag)] srcFormat=\(srcFormat) destFormat=\(dest)")
            convertLogCount += 1
        }

        // 源与目标完全一致，直接填 buffer
        if srcFormat.sampleRate == dest.sampleRate, srcFormat.channelCount == dest.channelCount, srcFormat.commonFormat == dest.commonFormat {
            let bytesPerSample = isFloat ? 4 : 2
            let fc = data.count / (Int(srcFormat.channelCount) * bytesPerSample)
            return createSourcePCMBuffer(from: data, format: srcFormat, frameCount: fc, channels: Int(srcFormat.channelCount), interleaved: interleaved, isFloat: isFloat)
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: dest) else {
            print("[\(logTag)] Failed to create AVAudioConverter")
            return createPCMBufferFromRaw(data, destFormat: destFormat)
        }

        let bytesPerFrame = (isFloat ? 4 : 2) * channels
        let frameCount = data.count / bytesPerFrame
        guard frameCount > 0,
              let srcBuffer = createSourcePCMBuffer(from: data, format: srcFormat, frameCount: frameCount, channels: channels, interleaved: interleaved, isFloat: isFloat) else {
            return createPCMBufferFromRaw(data, destFormat: destFormat)
        }

        let ratio = dest.sampleRate / srcFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(frameCount) * ratio + 64)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: dest, frameCapacity: outCapacity) else {
            return createPCMBufferFromRaw(data, destFormat: destFormat)
        }

        // 使用 block-based API：支持采样率转换（简单 convert(to:from:) 不支持 SRC，报 -50）
        var inputProvided = false
        var convertError: NSError?
        let status = converter.convert(to: outBuffer, error: &convertError) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return srcBuffer
        }

        if let convertError = convertError {
            print("[\(logTag)] AVAudioConverter block-based convert error: \(convertError)")
            return createPCMBufferFromRaw(data, destFormat: destFormat)
        }
        if status == .error {
            print("[\(logTag)] AVAudioConverter convert status=error")
            return createPCMBufferFromRaw(data, destFormat: destFormat)
        }
        guard outBuffer.frameLength > 0 else {
            return createPCMBufferFromRaw(data, destFormat: destFormat)
        }
        return outBuffer
    }

    /// 无格式信息或转换失败时的回退：按 16k 单声道 Int16 解析（与常见 native 格式一致）
    private func createPCMBufferFromRaw(_ data: Data, destFormat: AVAudioFormat?) -> AVAudioPCMBuffer? {
        guard !data.isEmpty else { return nil }
        return createPCMBuffer16kMonoInt16(from: data)
    }

    private func createSourcePCMBuffer(from data: Data, format: AVAudioFormat, frameCount: Int, channels: Int, interleaved: Bool, isFloat: Bool) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let bytesPerChannel = data.count / channels
        let bytesPerSample = isFloat ? 4 : 2
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            guard let base = raw.baseAddress else { return }
            if interleaved {
                for ch in 0..<channels {
                    if isFloat, let dst = buffer.floatChannelData?[ch] {
                        for f in 0..<frameCount {
                            memcpy(dst.advanced(by: f), base.advanced(by: f * (bytesPerSample * channels) + ch * bytesPerSample), bytesPerSample)
                        }
                    } else if let dst = buffer.int16ChannelData?[ch] {
                        for f in 0..<frameCount {
                            memcpy(dst.advanced(by: f), base.advanced(by: f * (bytesPerSample * channels) + ch * bytesPerSample), bytesPerSample)
                        }
                    }
                }
            } else {
                for ch in 0..<channels {
                    if isFloat, let dst = buffer.floatChannelData?[ch] {
                        memcpy(dst, base.advanced(by: ch * bytesPerChannel), bytesPerChannel)
                    } else if let dst = buffer.int16ChannelData?[ch] {
                        memcpy(dst, base.advanced(by: ch * bytesPerChannel), bytesPerChannel)
                    }
                }
            }
        }
        return buffer
    }

    private func createPCMBuffer16kMonoInt16(from data: Data) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false) else { return nil }
        let frameCount = AVAudioFrameCount(data.count / 2)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        pcmBuffer.frameLength = frameCount
        if let channelData = pcmBuffer.int16ChannelData {
            data.withUnsafeBytes { raw in
                if let base = raw.baseAddress { memcpy(channelData[0], base, data.count) }
            }
        }
        return pcmBuffer
    }
}


// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case notAvailable
    case permissionDenied
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Screen recording is not available on this device"
        case .permissionDenied:
            return "Screen recording permission was denied"
        case .recordingFailed:
            return "Failed to start recording"
        }
    }
}
