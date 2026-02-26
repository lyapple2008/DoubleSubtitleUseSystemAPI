import SwiftUI
import AVFoundation
import ReplayKit

/// Main content view for the bilingual subtitle app
struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    /// 为 true 时触发隐藏的 RPSystemBroadcastPickerView，弹出系统 broadcast 选择窗口
    @State private var triggerSystemPicker = false

    var body: some View {
        VStack(spacing: 0) {
            LanguageSelectorView(
                sourceLanguage: $viewModel.sourceLanguage,
                targetLanguage: $viewModel.targetLanguage
            )
            .padding()

            SubtitleDisplayView(
                currentSubtitle: viewModel.currentSubtitle,
                historySubtitles: viewModel.historySubtitles
            )

            Spacer()

            VStack(spacing: 16) {
                if viewModel.isProcessing {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.isRecording {
                    Button(action: {
                        triggerSystemPicker = true
                        viewModel.stopRecording()
                    }) {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2)
                            Text("停止识别")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(viewModel.isProcessing)

                    Button(action: { viewModel.togglePiP() }) {
                        HStack {
                            Image(systemName: viewModel.isPiPActive ? "pip.exit" : "pip.enter")
                                .font(.title2)
                            Text(viewModel.isPiPActive ? "退出画中画" : "开启画中画")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                } else {
                    // 开始识别按钮：点击后触发 RPSystemBroadcastPickerView，弹出系统自带选择窗口
                    Button(action: {
                        viewModel.startRecording {
                            triggerSystemPicker = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                            Text("开始识别")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(viewModel.isProcessing)
                }
            }
            .padding()
            .background(Color(.systemGray6))
        }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .background(
            // 隐藏的 RPSystemBroadcastPickerView，由「开始识别」按钮通过 triggerSystemPicker 触发
            BroadcastPickerView(
                preferredExtension: "com.doublesubtitle.app.AudioCaptureExtension",
                trigger: $triggerSystemPicker
            )
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
        )
    }
}

/// ViewModel for ContentView
@MainActor
final class ContentViewModel: NSObject, ObservableObject {
    @Published var sourceLanguage: LanguageOption = .defaultSource {
        didSet {
            TranslationManager.shared.configure(source: sourceLanguage, target: targetLanguage)
        }
    }

    @Published var targetLanguage: LanguageOption = .defaultTarget {
        didSet {
            TranslationManager.shared.configure(source: sourceLanguage, target: targetLanguage)
        }
    }

    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isPiPActive = false
    @Published var statusMessage = ""
    @Published var showError = false
    @Published var errorMessage = ""

    @Published var currentSubtitle: SubtitleItem?
    @Published var historySubtitles: [SubtitleItem] = []

    private var subtitleOverlayManager = SubtitleOverlayManager.shared

    private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?

    override init() {
        super.init()
        TranslationManager.shared.configure(source: sourceLanguage, target: targetLanguage)
    }

    /// 用户点击「开始识别」后调用，先请求权限并准备，再通过 onReadyToShowPicker 触发系统 RPSystemBroadcastPickerView。
    func startRecording(onReadyToShowPicker: @escaping () -> Void) {
        requestPermissions { [weak self] granted in
            guard granted else {
                Task { @MainActor in
                    self?.showError(message: "需要语音识别权限")
                }
                return
            }
            Task { @MainActor in
                self?.performPrepareAndShowPicker(onReadyToShowPicker: onReadyToShowPicker)
            }
        }
    }

    private func performPrepareAndShowPicker(onReadyToShowPicker: @escaping () -> Void) {
        AudioCaptureManager.shared.delegate = self
        SpeechRecognitionManager.shared.delegate = self
        SpeechRecognitionManager.shared.configure(locale: sourceLanguage.locale)
        AudioCaptureManager.shared.startWaitingForBroadcastStart()
        onReadyToShowPicker()
    }

    func stopRecording() {
        AudioCaptureManager.shared.stopCapture()
        SpeechRecognitionManager.shared.stopRecognition()
        subtitleOverlayManager.stopPiP()

        isRecording = false
        currentSubtitle = nil
    }

    func togglePiP() {
        if isPiPActive {
            subtitleOverlayManager.stopPiP()
            isPiPActive = false
        } else {
            startPiP()
        }
    }

    private func startPiP() {
        if sampleBufferDisplayLayer == nil {
            let layer = AVSampleBufferDisplayLayer()
            layer.videoGravity = .resizeAspect
            sampleBufferDisplayLayer = layer
        }

        if let layer = sampleBufferDisplayLayer {
            subtitleOverlayManager.setupPiP(with: layer)
            subtitleOverlayManager.startPiP()
            isPiPActive = true
        }
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        // Request speech recognition permission only (no microphone needed for system audio)
        SpeechRecognitionManager.shared.requestPermission { speechGranted in
            completion(speechGranted)
        }
    }

    private func translateText(_ text: String) {
        Task {
            do {
                let translatedText = try await TranslationManager.shared.translate(text)

                await MainActor.run {
                    if let existingSubtitle = currentSubtitle {
                        currentSubtitle = SubtitleItem(
                            id: existingSubtitle.id,
                            originalText: existingSubtitle.originalText,
                            translatedText: translatedText,
                            timestamp: existingSubtitle.timestamp,
                            isFinal: existingSubtitle.isFinal
                        )
                    }
                }
            } catch {
                print("Translation error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - AudioCaptureDelegate

extension ContentViewModel: AudioCaptureDelegate {
    nonisolated func audioCaptureDidStart() {
        Task { @MainActor in
            isRecording = true
            statusMessage = "音频捕获中..."
            SpeechRecognitionManager.shared.startRecognition()
        }
    }

    nonisolated func audioCaptureDidStop() {
        Task { @MainActor in
            statusMessage = ""
        }
    }

    nonisolated func audioCaptureDidReceiveAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Forward to speech recognition
        SpeechRecognitionManager.shared.processAudioBuffer(buffer)
    }

    nonisolated func audioCaptureDidFail(with error: Error) {
        Task { @MainActor in
            showError(message: error.localizedDescription)
            stopRecording()
        }
    }
}

// MARK: - SpeechRecognitionDelegate

extension ContentViewModel: SpeechRecognitionDelegate {
    nonisolated func speechRecognitionDidStart() {
        Task { @MainActor in
            statusMessage = "语音识别中..."
        }
    }

    nonisolated func speechRecognitionDidStop() {
        Task { @MainActor in
            statusMessage = ""
        }
    }

    nonisolated func speechRecognitionDidReceiveResult(_ result: String, isFinal: Bool) {
        Task { @MainActor in
            if isFinal {
                // Final result - add to history and translate
                let translatedText = "翻译中..."

                let newSubtitle = SubtitleItem(
                    originalText: result,
                    translatedText: translatedText,
                    isFinal: true
                )

                // Add to history
                historySubtitles.append(newSubtitle)
                currentSubtitle = nil

                // Trigger translation
                translateText(result)

                // Update subtitle overlay
                subtitleOverlayManager.updateSubtitle(newSubtitle)
            } else {
                // Interim result - show as current
                currentSubtitle = SubtitleItem(
                    originalText: result,
                    translatedText: "翻译中...",
                    isFinal: false
                )
            }
        }
    }

    nonisolated func speechRecognitionDidFail(with error: Error) {
        Task { @MainActor in
            showError(message: error.localizedDescription)
            stopRecording()
        }
    }
}

#Preview {
    ContentView()
}
