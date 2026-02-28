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
    private var segmentationTimer: Timer?
    private var recognitionTranscript: String = ""
    private var committedTranscriptCharCount: Int = 0
    private var lastResultChangedAt: Date = .distantPast
    private var lastUncommittedText: String = ""
    private var stableUncommittedCount: Int = 0
    private var lastCommittedNormalizedText: String = ""
    private var pendingWeakPunctuationCommitChars: Int?
    private var pendingWeakPunctuationDetectedAt: Date = .distantPast
    private let weakPunctuationDelay: TimeInterval = 0.3
    private let silenceCommitInterval: TimeInterval = 0.5
    private let stableCommitThreshold: Int = 2
    private let minStableCommitChars: Int = 6
    private let minWeakPunctuationCommitChars: Int = 10
    private let maxUncommittedCommitChars: Int = 22
    private let minSilenceCommitChars: Int = 2

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
        commitRemainingUncommitted(reason: "manual-stop")
        stopSegmentationTimer()
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

    private func translateText(for subtitleID: UUID, text: String) {
        Task {
            do {
                let translatedText = try await TranslationManager.shared.translate(text)

                await MainActor.run {
                    print("[ContentViewModel] translation updated subtitleID=\(subtitleID) translated=\"\(translatedText)\"")
                    updateTranslatedSubtitle(subtitleID: subtitleID, translatedText: translatedText)
                }
            } catch {
                print("Translation error: \(error.localizedDescription)")
                await MainActor.run {
                    print("[ContentViewModel] translation failed subtitleID=\(subtitleID) error=\(error.localizedDescription)")
                    updateTranslatedSubtitle(subtitleID: subtitleID, translatedText: "翻译失败")
                }
            }
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
    }

    private func startSegmentationTimer() {
        stopSegmentationTimer()
        segmentationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleSilenceCommitIfNeeded()
            }
        }
        if let timer = segmentationTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopSegmentationTimer() {
        segmentationTimer?.invalidate()
        segmentationTimer = nil
    }

    private func resetSegmentationState() {
        recognitionTranscript = ""
        committedTranscriptCharCount = 0
        lastResultChangedAt = Date.distantPast
        lastUncommittedText = ""
        stableUncommittedCount = 0
        lastCommittedNormalizedText = ""
        pendingWeakPunctuationCommitChars = nil
        pendingWeakPunctuationDetectedAt = .distantPast
    }

    private func handleRecognitionResultText(_ result: String, isFinal: Bool) {
        let normalized = normalizeForComparison(result)
        if normalized != recognitionTranscript {
            recognitionTranscript = normalized
            lastResultChangedAt = Date()
        }

        if committedTranscriptCharCount > recognitionTranscript.count {
            committedTranscriptCharCount = 0
        }

        clearPendingWeakPunctuationCandidateIfInvalid()

        commitByStrongPunctuationIfNeeded()

        var uncommitted = uncommittedTranscript()
        if commitByWeakPunctuationIfNeeded(uncommitted) {
            uncommitted = uncommittedTranscript()
        }
        if commitPendingWeakPunctuationIfNeeded() {
            uncommitted = uncommittedTranscript()
        }
        if commitByMaxLengthIfNeeded(uncommitted) {
            uncommitted = uncommittedTranscript()
        }

        if uncommitted == lastUncommittedText {
            stableUncommittedCount += 1
        } else {
            lastUncommittedText = uncommitted
            stableUncommittedCount = 1
        }

        if !isFinal,
           stableUncommittedCount >= stableCommitThreshold,
           uncommitted.count >= minStableCommitChars {
            commitUncommitted(reason: "stable")
            uncommitted = uncommittedTranscript()
        }

        if isFinal {
            commitRemainingUncommitted(reason: "final")
            return
        }

        updateCurrentSubtitlePreview(uncommitted)
    }

    private func handleSilenceCommitIfNeeded() {
        guard isRecording else { return }
        if commitPendingWeakPunctuationIfNeeded() { return }
        let uncommitted = uncommittedTranscript()
        if commitByMaxLengthIfNeeded(uncommitted) { return }
        guard lastResultChangedAt != .distantPast else { return }
        guard Date().timeIntervalSince(lastResultChangedAt) >= silenceCommitInterval else { return }
        guard uncommitted.count >= minSilenceCommitChars else { return }
        commitUncommitted(reason: "silence")
    }

    private func commitByStrongPunctuationIfNeeded() {
        while true {
            let uncommitted = uncommittedTranscript()
            guard let commitLen = commitLengthToLastStrongTerminator(in: uncommitted) else { break }
            let segment = String(uncommitted.prefix(commitLen))
            guard commitRecognizedSegment(segment, reason: "strong-punctuation") else { break }
            clearPendingWeakPunctuationCandidateIfInvalid()
        }
    }

    private func commitByWeakPunctuationIfNeeded(_ uncommitted: String) -> Bool {
        guard let commitLen = commitLengthToLastWeakTerminator(in: uncommitted) else { return false }
        if commitLen >= minWeakPunctuationCommitChars {
            let segment = String(uncommitted.prefix(commitLen))
            if commitRecognizedSegment(segment, reason: "weak-punctuation-length") {
                clearPendingWeakPunctuationCandidateIfInvalid()
                return true
            }
            return false
        }
        updatePendingWeakPunctuationCandidate(commitLen: commitLen)
        return false
    }

    private func commitPendingWeakPunctuationIfNeeded() -> Bool {
        guard let pendingChars = pendingWeakPunctuationCommitChars else { return false }
        guard pendingChars > committedTranscriptCharCount else {
            clearPendingWeakPunctuationCandidate()
            return false
        }
        guard pendingChars <= recognitionTranscript.count else { return false }
        guard pendingWeakPunctuationDetectedAt != .distantPast else { return false }
        guard Date().timeIntervalSince(pendingWeakPunctuationDetectedAt) >= weakPunctuationDelay else { return false }
        guard let segment = transcriptSlice(from: committedTranscriptCharCount, to: pendingChars) else { return false }
        let committed = commitRecognizedSegment(segment, reason: "weak-punctuation-timeout")
        clearPendingWeakPunctuationCandidate()
        return committed
    }

    private func commitByMaxLengthIfNeeded(_ uncommitted: String) -> Bool {
        guard uncommitted.count >= maxUncommittedCommitChars else { return false }
        let commitLen = bestCutLengthForMaxCommit(in: uncommitted)
        guard commitLen > 0 else { return false }
        let segment = String(uncommitted.prefix(commitLen))
        return commitRecognizedSegment(segment, reason: "max-length")
    }

    private func updatePendingWeakPunctuationCandidate(commitLen: Int) {
        let absolute = committedTranscriptCharCount + commitLen
        guard absolute <= recognitionTranscript.count else { return }
        if pendingWeakPunctuationCommitChars != absolute {
            pendingWeakPunctuationCommitChars = absolute
            pendingWeakPunctuationDetectedAt = Date()
        }
    }

    private func clearPendingWeakPunctuationCandidateIfInvalid() {
        guard let pending = pendingWeakPunctuationCommitChars else { return }
        if pending <= committedTranscriptCharCount || pending > recognitionTranscript.count {
            clearPendingWeakPunctuationCandidate()
        }
    }

    private func clearPendingWeakPunctuationCandidate() {
        pendingWeakPunctuationCommitChars = nil
        pendingWeakPunctuationDetectedAt = .distantPast
    }

    private func commitRemainingUncommitted(reason: String) {
        commitUncommitted(reason: reason)
        currentSubtitle = nil
    }

    private func commitUncommitted(reason: String) {
        let uncommitted = uncommittedTranscript()
        guard !uncommitted.isEmpty else { return }
        _ = commitRecognizedSegment(uncommitted, reason: reason)
    }

    @discardableResult
    private func commitRecognizedSegment(_ rawText: String, reason: String) -> Bool {
        let committed = normalizeCommittedText(rawText)
        guard !committed.isEmpty else {
            committedTranscriptCharCount += rawText.count
            clearPendingWeakPunctuationCandidateIfInvalid()
            return false
        }
        if committed == lastCommittedNormalizedText {
            committedTranscriptCharCount += rawText.count
            clearPendingWeakPunctuationCandidateIfInvalid()
            return false
        }

        let item = SubtitleItem(
            originalText: committed,
            translatedText: "翻译中...",
            isFinal: true
        )
        historySubtitles.append(item)
        subtitleOverlayManager.updateSubtitle(item)
        translateText(for: item.id, text: committed)

        committedTranscriptCharCount += rawText.count
        lastCommittedNormalizedText = committed
        lastUncommittedText = uncommittedTranscript()
        stableUncommittedCount = 0
        clearPendingWeakPunctuationCandidateIfInvalid()
        print("[ContentViewModel] committed reason=\(reason) text=\"\(committed)\"")
        return true
    }

    private func updateCurrentSubtitlePreview(_ uncommitted: String) {
        let preview = normalizeCommittedText(uncommitted)
        if preview.isEmpty {
            currentSubtitle = nil
            return
        }
        currentSubtitle = SubtitleItem(
            originalText: preview,
            translatedText: "翻译中...",
            isFinal: false
        )
    }

    private func uncommittedTranscript() -> String {
        guard committedTranscriptCharCount < recognitionTranscript.count else { return "" }
        let idx = recognitionTranscript.index(recognitionTranscript.startIndex, offsetBy: committedTranscriptCharCount)
        return String(recognitionTranscript[idx...])
    }

    private func commitLengthToLastStrongTerminator(in text: String) -> Int? {
        var last: Int?
        let terminators: Set<Character> = ["。", "！", "？", ".", "!", "?", ";", "；", "\n"]
        for (i, ch) in text.enumerated() where terminators.contains(ch) {
            last = i + 1
        }
        return last
    }

    private func commitLengthToLastWeakTerminator(in text: String) -> Int? {
        var last: Int?
        let weakTerminators: Set<Character> = ["，", "、", ",", ":", "："]
        for (i, ch) in text.enumerated() where weakTerminators.contains(ch) {
            last = i + 1
        }
        return last
    }

    private func bestCutLengthForMaxCommit(in text: String) -> Int {
        let hardLimit = maxUncommittedCommitChars
        var idx = 0
        var lastBreak: Int?
        let strong: Set<Character> = ["。", "！", "？", ".", "!", "?", ";", "；", "\n"]
        let weak: Set<Character> = ["，", "、", ",", ":", "："]

        for ch in text {
            idx += 1
            if idx > hardLimit { break }
            if strong.contains(ch) {
                lastBreak = idx
            } else if weak.contains(ch) {
                lastBreak = idx
            } else if ch.isWhitespace || ch.isNewline {
                lastBreak = idx
            }
        }
        return lastBreak ?? hardLimit
    }

    private func transcriptSlice(from startCount: Int, to endCount: Int) -> String? {
        guard startCount >= 0, endCount >= startCount, endCount <= recognitionTranscript.count else { return nil }
        let start = recognitionTranscript.index(recognitionTranscript.startIndex, offsetBy: startCount)
        let end = recognitionTranscript.index(recognitionTranscript.startIndex, offsetBy: endCount)
        return String(recognitionTranscript[start..<end])
    }

    private func normalizeCommittedText(_ text: String) -> String {
        let parts = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeForComparison(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AudioCaptureDelegate

extension ContentViewModel: AudioCaptureDelegate {
    nonisolated func audioCaptureDidStart() {
        Task { @MainActor in
            isRecording = true
            statusMessage = "音频捕获中..."
            resetSegmentationState()
            startSegmentationTimer()
            SpeechRecognitionManager.shared.startRecognition()
        }
    }

    nonisolated func audioCaptureDidStop() {
        Task { @MainActor in
            stopSegmentationTimer()
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
            commitRemainingUncommitted(reason: "recognition-stop")
            stopSegmentationTimer()
            statusMessage = ""
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
