import Foundation
import Speech
import AVFoundation

/// Protocol for receiving speech recognition events
protocol SpeechRecognitionDelegate: AnyObject {
    func speechRecognitionDidStart()
    func speechRecognitionDidStop()
    func speechRecognitionDidReceiveResult(_ result: String, isFinal: Bool)
    func speechRecognitionDidFail(with error: Error)
}

/// Manages real-time speech recognition using SFSpeechRecognizer
final class SpeechRecognitionManager: NSObject {
    static let shared = SpeechRecognitionManager()

    /// 日志 tag，控制台过滤可用此字符串（如：SpeechRecognitionManager）
    private let logTag = "SpeechRecognitionManager"

    weak var delegate: SpeechRecognitionDelegate?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var currentLocale: Locale = Locale(identifier: "en-US")
    private var _isRecognizing = false

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Check if speech recognition is available
    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    /// Check if currently recognizing
    var isRecognizing: Bool {
        _isRecognizing
    }

    /// 识别请求期望的音频格式（官方文档：append 的 buffer 须为 native format）。主 App 转换 Extension 的 raw 时应转成此格式。
    var preferredRecognitionFormat: AVAudioFormat? {
        recognitionRequest?.nativeAudioFormat
    }

    /// Request speech recognition permission
    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    /// Configure the recognizer with a specific locale
    func configure(locale: Locale) {
        currentLocale = locale
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        speechRecognizer?.delegate = self
        print("[\(logTag)] configure locale: \(locale.identifier)")
    }

    /// Start speech recognition from external audio buffer (e.g., from ReplayKit)
    func startRecognition() {
        guard !_isRecognizing else { return }

        // Configure speech recognizer if not already configured
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
            speechRecognizer?.delegate = self
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            delegate?.speechRecognitionDidFail(with: SpeechRecognitionError.notAvailable)
            return
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Create recognition request for external audio (no audio session needed)
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            delegate?.speechRecognitionDidFail(with: SpeechRecognitionError.requestCreationFailed)
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 16, *) {
            recognitionRequest.addsPunctuation = true
        }

        if #available(iOS 16, *) {
            recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        }

        // Start recognition task (waiting for external audio buffers)
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                if !text.isEmpty {
                    print("[\(self.logTag)] 识别结果 isFinal=\(isFinal) text=\"\(text)\"")
                }
                self.delegate?.speechRecognitionDidReceiveResult(text, isFinal: isFinal)
            }

            if let error = error {
                print("[\(self.logTag)] recognition task error: \(error.localizedDescription)")
            }

            if error != nil || (result?.isFinal ?? false) {
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self._isRecognizing = false
                self.delegate?.speechRecognitionDidStop()
                print("[\(self.logTag)] recognition stopped")
            }
        }

        _isRecognizing = true
        processAudioBufferCallCount = 0
        delegate?.speechRecognitionDidStart()
        print("[\(logTag)] startRecognition locale=\(currentLocale.identifier) waiting for audio buffers")
    }

    /// Stop speech recognition
    func stopRecognition() {
        guard isRecognizing else { return }

        print("[\(logTag)] stopRecognition")
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        _isRecognizing = false

        delegate?.speechRecognitionDidStop()
    }

    /// Process audio buffer from external source (e.g., ReplayKit)
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecognizing, let recognitionRequest = recognitionRequest else {
            print("[\(logTag)] processAudioBuffer skipped (not recognizing)")
            return
        }
        let frameLength = buffer.frameLength
        let format = buffer.format
        recognitionRequest.append(buffer)
        // 每 50 次或首帧打一次日志，避免刷屏
        if processAudioBufferCallCount % 50 == 0 || processAudioBufferCallCount == 0 {
            print("[\(logTag)] processAudioBuffer appended frameLength=\(frameLength) format=\(String(describing: format))")
        }
        processAudioBufferCallCount += 1
    }

    private var processAudioBufferCallCount: Int = 0
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechRecognitionManager: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        print("[\(logTag)] availabilityDidChange available=\(available)")
        if !available && isRecognizing {
            stopRecognition()
            delegate?.speechRecognitionDidFail(with: SpeechRecognitionError.notAvailable)
        }
    }
}

// MARK: - Errors

enum SpeechRecognitionError: LocalizedError {
    case notAvailable
    case permissionDenied
    case requestCreationFailed

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Speech recognition is not available"
        case .permissionDenied:
            return "Speech recognition permission was denied"
        case .requestCreationFailed:
            return "Failed to create recognition request"
        }
    }
}
