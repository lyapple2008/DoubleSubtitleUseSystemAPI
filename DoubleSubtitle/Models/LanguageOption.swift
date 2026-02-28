import Foundation
import Speech

/// Represents a language option for translation
struct LanguageOption: Identifiable, Hashable {
    let id: String
    let code: String
    let displayName: String
    let locale: Locale

    init(code: String, displayName: String) {
        self.id = code
        self.code = code
        self.displayName = displayName
        self.locale = Locale(identifier: code)
    }

    static let supportedLanguages: [LanguageOption] = [
        LanguageOption(code: "en-US", displayName: "English"),
        LanguageOption(code: "zh-Hans-CN", displayName: "简体中文"),
        LanguageOption(code: "zh-Hant-TW", displayName: "繁體中文"),
        LanguageOption(code: "ja-JP", displayName: "日本語"),
        LanguageOption(code: "ko-KR", displayName: "한국어"),
        LanguageOption(code: "fr-FR", displayName: "Français"),
        LanguageOption(code: "de-DE", displayName: "Deutsch"),
        LanguageOption(code: "es-ES", displayName: "Español"),
        LanguageOption(code: "pt-BR", displayName: "Português"),
        LanguageOption(code: "it-IT", displayName: "Italiano"),
        LanguageOption(code: "ru-RU", displayName: "Русский"),
        LanguageOption(code: "ar-SA", displayName: "العربية")
    ]

    static let sourceLanguages: [LanguageOption] = supportedLanguages.filter { code in
        ["en-US", "zh-Hans-CN", "zh-Hant-TW", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES"].contains(code.code)
    }

    static let targetLanguages: [LanguageOption] = supportedLanguages.filter { code in
        // Allow all languages as targets except the source languages to avoid same-language translation
        true
    }

    static var defaultSource: LanguageOption {
        LanguageOption(code: "zh-Hans-CN", displayName: "简体中文")
    }

    static var defaultTarget: LanguageOption {
        LanguageOption(code: "en-US", displayName: "English")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: LanguageOption, rhs: LanguageOption) -> Bool {
        lhs.id == rhs.id
    }
}
