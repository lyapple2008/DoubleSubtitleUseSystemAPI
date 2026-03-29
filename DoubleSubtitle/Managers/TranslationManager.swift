import Foundation
import NaturalLanguage

// Import Translation framework only for iOS 18+
#if canImport(Translation)
import Translation
#endif

/// Protocol for receiving translation events
protocol TranslationDelegate: AnyObject {
    func translationDidComplete(originalText: String, translatedText: String)
    func translationDidFail(with error: Error)
}

/// Manages text translation using system Translation framework (iOS 17+)
final class TranslationManager: NSObject, ObservableObject {
    static let shared = TranslationManager()
    private let logTag = "TranslationManager"

    weak var delegate: TranslationDelegate?

    @Published var isTranslating = false

    private var sourceLanguage: LanguageOption = .defaultSource
    private var targetLanguage: LanguageOption = .defaultTarget

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Configure source and target languages
    func configure(source: LanguageOption, target: LanguageOption) {
        self.sourceLanguage = source
        self.targetLanguage = target
    }

    /// Translate text from source to target language
    @MainActor
    func translate(_ text: String) async throws -> String {
        guard !text.isEmpty else { return "" }

        isTranslating = true
        defer { isTranslating = false }
        print("[\(logTag)] translate start source=\(sourceLanguage.code) target=\(targetLanguage.code) text=\"\(text)\"")

        do {
            if #available(iOS 26.0, *) {
                return try await translateWithSystemAPI(text)
            } else {
                return try await translateWithPlaceholder(text)
            }
        } catch {
            delegate?.translationDidFail(with: error)
            throw error
        }
    }

    @available(iOS 26.0, *)
    private func translateWithSystemAPI(_ text: String) async throws -> String {
        #if canImport(Translation)
        // Use system Translation framework
        let sourceLanguageCode = Locale.Language(identifier: sourceLanguage.code)
        let targetLanguageCode = Locale.Language(identifier: targetLanguage.code)

        // Create translation session using the new API
        let session = TranslationSession(
            installedSource: sourceLanguageCode,
            target: targetLanguageCode
        )

        let response = try await session.translate(text)
        let translatedText = response.targetText
        print("[\(logTag)] translate success text=\"\(text)\" translated=\"\(translatedText)\"")

        delegate?.translationDidComplete(originalText: text, translatedText: translatedText)
        return translatedText
        #else
        return try await translateWithPlaceholder(text)
        #endif
    }

    private func translateWithPlaceholder(_ text: String) async throws -> String {
        // For iOS versions below 26.0, we use a placeholder
        // In a production app, you would integrate a third-party translation API
        let translatedText = "[翻译: \(text)]"
        print("[\(logTag)] translate placeholder text=\"\(text)\" translated=\"\(translatedText)\"")

        delegate?.translationDidComplete(originalText: text, translatedText: translatedText)
        return translatedText
    }

    /// Reset session when language changes
    func resetSession() {
        // No session to reset in current implementation
    }
}

// MARK: - Errors

enum TranslationError: LocalizedError {
    case notAvailable
    case translationFailed
    case languageNotSupported

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Translation is not available on this device"
        case .translationFailed:
            return "Translation failed"
        case .languageNotSupported:
            return "The selected language pair is not supported"
        }
    }
}
