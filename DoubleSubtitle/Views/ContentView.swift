import SwiftUI
import AVFoundation
import ReplayKit
import UIKit
import Combine

/// Main content view for the bilingual subtitle app
struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    /// 为 true 时触发隐藏的 RPSystemBroadcastPickerView，弹出系统 broadcast 选择窗口
    @State private var triggerSystemPicker = false

    var body: some View {
        VStack(spacing: 0) {
            LanguageSelectorView(
                sourceLanguage: $viewModel.sourceLanguage,
                targetLanguage: $viewModel.targetLanguage,
                sourceLanguageSupportsOnDeviceRecognition: viewModel.sourceLanguageSupportsOnDeviceRecognition
            )
            .padding()

            SubtitleDisplayView(
                currentSubtitle: viewModel.currentSubtitle,
                historySubtitles: viewModel.historySubtitles
            )
            .frame(maxHeight: .infinity, alignment: .top)

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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            viewModel.handleDidEnterBackground()
        }
    }
}

/// ViewModel for ContentView
@MainActor
final class ContentViewModel: NSObject, ObservableObject {
    @Published var sourceLanguage: LanguageOption = .defaultSource {
        didSet {
            TranslationManager.shared.configure(source: sourceLanguage, target: targetLanguage)
            sourceLanguageSupportsOnDeviceRecognition = SpeechRecognitionManager.shared.supportsOnDeviceRecognition(for: sourceLanguage.locale)
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
    @Published var sourceLanguageSupportsOnDeviceRecognition = false

    private var subtitleOverlayManager = SubtitleOverlayManager.shared
    private let sentenceSegmenter = SpeechSentenceSegmenter(
        maxSentenceLength: 30,
        pauseThreshold: 1.5
    )
    private var sentenceFlushTimer: Timer?
    private var translationQueue: [TranslationJob] = []
    private var isTranslationQueueRunning = false
    private var recentCommittedSegments: [CommittedSegmentRecord] = []
    private var currentSessionHistoryStartIndex = 0
    private var cancellables: Set<AnyCancellable> = []
    private let dedupeWindowSeconds: TimeInterval = 12
    private let dedupeWindowMaxItems = 40
    private let minimumSegmentContentLength = 2
    private let translatingPlaceholder = "翻译中..."

    private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?

    override init() {
        super.init()
        TranslationManager.shared.configure(source: sourceLanguage, target: targetLanguage)
        sourceLanguageSupportsOnDeviceRecognition = SpeechRecognitionManager.shared.supportsOnDeviceRecognition(for: sourceLanguage.locale)
        subtitleOverlayManager.$isPiPActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                self?.isPiPActive = active
            }
            .store(in: &cancellables)
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
        sentenceSegmenter.reset()
        recentCommittedSegments.removeAll()
        currentSubtitle = nil
        currentSessionHistoryStartIndex = historySubtitles.count
        subtitleOverlayManager.resetDisplayedTexts()
        AudioCaptureManager.shared.delegate = self
        SpeechRecognitionManager.shared.delegate = self
        SpeechRecognitionManager.shared.configure(locale: sourceLanguage.locale)
        AudioCaptureManager.shared.startWaitingForBroadcastStart()
        onReadyToShowPicker()
    }

    func stopRecording() {
        flushPendingSegments(force: true)
        stopSentenceFlushTimer()
        AudioCaptureManager.shared.stopCapture()
        SpeechRecognitionManager.shared.stopRecognition()
        subtitleOverlayManager.stopPiP()
        subtitleOverlayManager.resetDisplayedTexts()

        isRecording = false
        currentSubtitle = nil
    }

    func handleDidEnterBackground() {
        guard isRecording else { return }
        guard !subtitleOverlayManager.isActive else { return }
        startPiP()
    }

    func togglePiP() {
        if isPiPActive {
            subtitleOverlayManager.stopPiP()
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

    private func updateTranslatedSubtitle(subtitleID: UUID, translatedText: String) {
        guard let index = historySubtitles.lastIndex(where: { $0.id == subtitleID }) else { return }
        let old = historySubtitles[index]
        let updated = SubtitleItem(
            id: old.id,
            originalText: old.originalText,
            translatedText: translatedText,
            timestamp: old.timestamp,
            isFinal: old.isFinal
        )
        historySubtitles[index] = updated
        subtitleOverlayManager.updateSubtitle(updated)
        syncPiPTranslatedTextFromCurrentSession()
    }

    private func submitRecognizedSegment(_ segment: SegmentedSentence) {
        let now = Date()
        let text = normalizeSegmentText(segment.text)
        guard !text.isEmpty else { return }
        print("[ContentViewModel] 断句触发 reason=\(segment.reason.rawValue) label=\(segment.reason.logLabel) text=\"\(text)\"")
        guard containsContentCharacter(text) else {
            print("[ContentViewModel] skip punctuation-only segment text=\"\(text)\"")
            return
        }
        guard contentCharacterCount(in: text) >= minimumSegmentContentLength else {
            print("[ContentViewModel] skip short segment text=\"\(text)\"")
            return
        }
        guard !isDuplicateSegment(text, now: now) else {
            print("[ContentViewModel] skip duplicate segment text=\"\(text)\"")
            return
        }
        markSegmentCommitted(text, at: now)

        let item = SubtitleItem(
            originalText: text,
            translatedText: "翻译中...",
            isFinal: true
        )
        historySubtitles.append(item)
        subtitleOverlayManager.updateSubtitle(item)
        syncPiPTranslatedTextFromCurrentSession()
        enqueueTranslation(subtitleID: item.id, text: text)
    }

    private func submitRecognizedSegments(_ segments: [SegmentedSentence]) {
        guard !segments.isEmpty else { return }
        for segment in segments {
            submitRecognizedSegment(segment)
        }
    }

    private func enqueueTranslation(subtitleID: UUID, text: String) {
        translationQueue.append(TranslationJob(subtitleID: subtitleID, text: text))
        processNextTranslationIfNeeded()
    }

    private func processNextTranslationIfNeeded() {
        guard !isTranslationQueueRunning else { return }
        guard !translationQueue.isEmpty else { return }

        isTranslationQueueRunning = true
        let job = translationQueue.removeFirst()

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let translatedText = try await TranslationManager.shared.translate(job.text)
                await MainActor.run {
                    print("[ContentViewModel] translation updated subtitleID=\(job.subtitleID) translated=\"\(translatedText)\"")
                    self.updateTranslatedSubtitle(subtitleID: job.subtitleID, translatedText: translatedText)
                    self.isTranslationQueueRunning = false
                    self.processNextTranslationIfNeeded()
                }
            } catch {
                await MainActor.run {
                    print("[ContentViewModel] translation failed subtitleID=\(job.subtitleID) error=\(error.localizedDescription)")
                    self.updateTranslatedSubtitle(subtitleID: job.subtitleID, translatedText: "翻译失败")
                    self.isTranslationQueueRunning = false
                    self.processNextTranslationIfNeeded()
                }
            }
        }
    }

    private func startSentenceFlushTimer() {
        stopSentenceFlushTimer()
        sentenceFlushTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.flushPendingSegments(force: false)
            self.refreshCurrentSubtitlePreview()
        }
        if let sentenceFlushTimer = sentenceFlushTimer {
            RunLoop.main.add(sentenceFlushTimer, forMode: .common)
        }
    }

    private func stopSentenceFlushTimer() {
        sentenceFlushTimer?.invalidate()
        sentenceFlushTimer = nil
    }

    private func flushPendingSegments(force: Bool) {
        let segments = force
            ? sentenceSegmenter.flushRemaining(reason: .forceFlush)
            : sentenceSegmenter.flushOnPauseIfNeeded()
        submitRecognizedSegments(segments)
    }

    private func refreshCurrentSubtitlePreview(for liveText: String? = nil) {
        let fullText = liveText ?? sentenceSegmenter.lastResult
        let text = normalizeSegmentText(fullText)

        if text.isEmpty {
            currentSubtitle = nil
            subtitleOverlayManager.updateCurrentOriginalText("")
            return
        }

        currentSubtitle = SubtitleItem(
            originalText: text,
            translatedText: "",
            isFinal: false
        )
        subtitleOverlayManager.updateCurrentOriginalText(text)
    }

    /// 处理识别结果，按稳定前缀断句并加入翻译队列
    private func handleRecognitionResultText(_ result: String, isFinal: Bool) {
        if !result.isEmpty {
            let stableSegments = sentenceSegmenter.processResult(result)
            submitRecognizedSegments(stableSegments)
        }

        if isFinal {
            submitRecognizedSegments(sentenceSegmenter.flushRemaining(reason: .final))
            sentenceSegmenter.reset()
            currentSubtitle = nil
            subtitleOverlayManager.updateCurrentOriginalText("")
        } else {
            refreshCurrentSubtitlePreview(for: result)
        }
    }

    private func syncPiPTranslatedTextFromCurrentSession() {
        guard currentSessionHistoryStartIndex < historySubtitles.count else {
            subtitleOverlayManager.updateCurrentTranslatedText("")
            return
        }

        let sessionItems = historySubtitles[currentSessionHistoryStartIndex...]
        let mergedTranslated = sessionItems
            .compactMap { item -> String? in
                let text = item.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                guard text != translatingPlaceholder else { return nil }
                return text
            }
            .joined(separator: "")
        subtitleOverlayManager.updateCurrentTranslatedText(mergedTranslated)
    }

    private func normalizeSegmentText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsContentCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
    }

    private func contentCharacterCount(in text: String) -> Int {
        text.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                count += 1
            }
        }
    }

    private func isDuplicateSegment(_ text: String, now: Date) -> Bool {
        pruneCommittedSegments(now: now)
        return recentCommittedSegments.contains {
            $0.text == text && now.timeIntervalSince($0.timestamp) <= dedupeWindowSeconds
        }
    }

    private func markSegmentCommitted(_ text: String, at now: Date) {
        pruneCommittedSegments(now: now)
        recentCommittedSegments.append(CommittedSegmentRecord(text: text, timestamp: now))
        if recentCommittedSegments.count > dedupeWindowMaxItems {
            let overflow = recentCommittedSegments.count - dedupeWindowMaxItems
            recentCommittedSegments.removeFirst(overflow)
        }
    }

    private func pruneCommittedSegments(now: Date) {
        recentCommittedSegments.removeAll {
            now.timeIntervalSince($0.timestamp) > dedupeWindowSeconds
        }
    }
}

// MARK: - AudioCaptureDelegate

extension ContentViewModel: AudioCaptureDelegate {
    nonisolated func audioCaptureDidStart() {
        Task { @MainActor in
            isRecording = true
            statusMessage = "音频捕获中..."
            startSentenceFlushTimer()
            SpeechRecognitionManager.shared.startRecognition()
        }
    }

    nonisolated func audioCaptureDidStop() {
        Task { @MainActor in
            flushPendingSegments(force: true)
            stopSentenceFlushTimer()
            isRecording = false
            statusMessage = ""
            subtitleOverlayManager.stopPiP()
            subtitleOverlayManager.resetDisplayedTexts()
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
            flushPendingSegments(force: true)
            stopSentenceFlushTimer()
            isRecording = false
            statusMessage = ""
            currentSubtitle = nil
            subtitleOverlayManager.stopPiP()
            subtitleOverlayManager.resetDisplayedTexts()
        }
    }

    nonisolated func speechRecognitionDidReceiveResult(_ result: String, isFinal: Bool) {
        Task { @MainActor in
            handleRecognitionResultText(result, isFinal: isFinal)
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

private struct TranslationJob {
    let subtitleID: UUID
    let text: String
}

private struct CommittedSegmentRecord {
    let text: String
    let timestamp: Date
}
