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

    weak var delegate: AudioCaptureDelegate?

    private let appGroupIdentifier = "group.com.doublesubtitle.app"
    private let broadcastActiveKey = "isBroadcastActive"
    private var isRecording = false
    private var fileMonitorTimer: Timer?
    private var broadcastStartPollTimer: Timer?
    private var lastReadPosition: UInt64 = 0
    private var broadcastPicker: RPSystemBroadcastPickerView?

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
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              defaults.bool(forKey: broadcastActiveKey) else {
            return
        }
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

        // Start monitoring the shared audio file
        fileMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkForNewAudioData()
        }
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

            print("[AudioCaptureManager] Read audio data, size: \(data.count) bytes")

            // Convert data to PCM buffer and notify delegate
            if !data.isEmpty, let pcmBuffer = createPCMBuffer(from: data) {
                print("[AudioCaptureManager] Created PCM buffer, format: \(String(describing: pcmBuffer.format))")
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.audioCaptureDidReceiveAudioBuffer(pcmBuffer)
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

    private func createPCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        // Create audio format - assuming 16kHz mono 16-bit PCM from Extension
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(data.count / Int(format.streamDescription.pointee.mBytesPerFrame))

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        pcmBuffer.frameLength = frameCount

        // Copy data to buffer
        if let channelData = pcmBuffer.int16ChannelData {
            data.withUnsafeBytes { rawBufferPointer in
                if let baseAddress = rawBufferPointer.baseAddress {
                    memcpy(channelData[0], baseAddress, data.count)
                }
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
