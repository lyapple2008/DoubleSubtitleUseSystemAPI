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
                self.delegate?.speechRecognitionDidReceiveResult(text, isFinal: isFinal)
            }

            if error != nil || (result?.isFinal ?? false) {
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self._isRecognizing = false
                self.delegate?.speechRecognitionDidStop()
            }
        }

        _isRecognizing = true
        delegate?.speechRecognitionDidStart()
        print("[SpeechRecognitionManager] Recognition started, waiting for external audio buffers")
    }

    /// Stop speech recognition
    func stopRecognition() {
        guard isRecognizing else { return }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        _isRecognizing = false

        delegate?.speechRecognitionDidStop()
    }

    /// Process audio buffer from external source (e.g., ReplayKit)
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        print("[SpeechRecognitionManager] Received external audio buffer, format: \(String(describing: buffer.format)), frames: \(buffer.frameLength)")

        guard isRecognizing, let recognitionRequest = recognitionRequest else {
            print("[SpeechRecognitionManager] Cannot process buffer - recognition not started")
            return
        }

        recognitionRequest.append(buffer)
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechRecognitionManager: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
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
