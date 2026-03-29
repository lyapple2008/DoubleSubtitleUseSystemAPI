import Foundation

/// Represents a subtitle item with original text and translation
struct SubtitleItem: Identifiable, Equatable {
    let id: UUID
    let originalText: String
    let translatedText: String
    let timestamp: Date
    var isFinal: Bool

    init(
        id: UUID = UUID(),
        originalText: String,
        translatedText: String,
        timestamp: Date = Date(),
        isFinal: Bool = false
    ) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.timestamp = timestamp
        self.isFinal = isFinal
    }

    static func == (lhs: SubtitleItem, rhs: SubtitleItem) -> Bool {
        lhs.id == rhs.id
    }
}
