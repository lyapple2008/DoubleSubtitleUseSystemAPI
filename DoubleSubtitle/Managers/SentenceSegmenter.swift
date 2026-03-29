import Foundation

enum SentenceBreakReason: String {
    case punctuation
    case length
    case pause
    case final
    case forceFlush

    var logLabel: String {
        switch self {
        case .punctuation:
            return "标点断句"
        case .length:
            return "长度断句"
        case .pause:
            return "停顿断句"
        case .final:
            return "final断句"
        case .forceFlush:
            return "强制flush断句"
        }
    }
}

struct SegmentedSentence {
    let text: String
    let reason: SentenceBreakReason
}

/// Segments streaming speech recognition text into stable sentences for translation.
final class SpeechSentenceSegmenter {
    private(set) var lastResult = ""
    private(set) var committedText = ""
    private(set) var lastUpdateTime = Date()

    private let punctuationPattern = "[，。！？；,.!?;]"
    private let maxSentenceLength: Int
    private let pauseThreshold: TimeInterval

    init(maxSentenceLength: Int, pauseThreshold: TimeInterval) {
        self.maxSentenceLength = maxSentenceLength
        self.pauseThreshold = pauseThreshold
    }

    var pendingPreviewText: String {
        remainingText(from: lastResult)
    }

    func processResult(_ text: String) -> [SegmentedSentence] {
        guard !text.isEmpty else {
            return []
        }

        let now = Date()

        if !committedText.isEmpty, !text.hasPrefix(committedText) {
            // 识别回退时，把提交边界回收到「committed 与 current 的公共前缀」，避免整段重复提交。
            committedText = longestCommonPrefix(committedText, text)
        }

        let stablePrefix = longestCommonPrefix(lastResult, text)
        var uncommittedStable = dropPrefix(stablePrefix, characterCount: committedText.count)
        var segments: [SegmentedSentence] = []

        while let sentence = extractSentence(from: uncommittedStable) {
            segments.append(sentence)
            committedText += sentence.text
            uncommittedStable = dropPrefix(uncommittedStable, characterCount: sentence.text.count)
        }

        lastResult = text
        lastUpdateTime = now
        return segments
    }

    func previewText(for text: String) -> String {
        guard !text.isEmpty else { return "" }
        return remainingText(from: text)
    }

    func flushOnPauseIfNeeded(now: Date = Date()) -> [SegmentedSentence] {
        guard now.timeIntervalSince(lastUpdateTime) > pauseThreshold else {
            return []
        }
        return flushRemaining(reason: .pause)
    }

    func flushRemaining(reason: SentenceBreakReason) -> [SegmentedSentence] {
        let remaining = remainingText(from: lastResult)
        guard !remaining.isEmpty else { return [] }
        committedText += remaining
        return [SegmentedSentence(text: remaining, reason: reason)]
    }

    func reset() {
        lastResult = ""
        committedText = ""
        lastUpdateTime = Date()
    }

    private func extractSentence(from text: String) -> SegmentedSentence? {
        guard !text.isEmpty else { return nil }

        if let range = text.range(of: punctuationPattern, options: .regularExpression) {
            return SegmentedSentence(text: String(text[..<range.upperBound]), reason: .punctuation)
        }

        if text.count >= maxSentenceLength {
            return SegmentedSentence(text: prefix(text, characterCount: maxSentenceLength), reason: .length)
        }

        return nil
    }

    private func remainingText(from text: String) -> String {
        guard !text.isEmpty else { return "" }
        guard !committedText.isEmpty else { return text }
        guard text.hasPrefix(committedText) else { return text }
        return dropPrefix(text, characterCount: committedText.count)
    }

    private func longestCommonPrefix(_ a: String, _ b: String) -> String {
        let aChars = Array(a)
        let bChars = Array(b)
        let maxCount = min(aChars.count, bChars.count)
        var index = 0
        while index < maxCount, aChars[index] == bChars[index] {
            index += 1
        }
        return String(aChars.prefix(index))
    }

    private func prefix(_ text: String, characterCount: Int) -> String {
        guard characterCount > 0 else { return "" }
        guard characterCount < text.count else { return text }
        let end = text.index(text.startIndex, offsetBy: characterCount)
        return String(text[..<end])
    }

    private func dropPrefix(_ text: String, characterCount: Int) -> String {
        guard characterCount > 0 else { return text }
        guard characterCount < text.count else { return "" }
        let start = text.index(text.startIndex, offsetBy: characterCount)
        return String(text[start...])
    }
}
