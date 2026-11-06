import Foundation

/// The spoken language tingjian listens for. Everything is translated into English.
public enum SourceLanguage: String, CaseIterable, Identifiable, Sendable {
    case mandarin
    case spanishLatinAmerica
    case french

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mandarin: "Mandarin"
        case .spanishLatinAmerica: "Spanish (Latin America)"
        case .french: "French"
        }
    }

    /// Short native label for compact UI.
    public var nativeName: String {
        switch self {
        case .mandarin: "中文"
        case .spanishLatinAmerica: "Español"
        case .french: "Français"
        }
    }

    /// Locale handed to the speech transcriber. es-419 resolves to es-MX.
    public var speechLocale: Locale {
        switch self {
        case .mandarin: Locale(identifier: "zh-CN")
        case .spanishLatinAmerica: Locale(identifier: "es-MX")
        case .french: Locale(identifier: "fr-FR")
        }
    }

    public var translationSource: Locale.Language {
        switch self {
        case .mandarin: Locale.Language(identifier: "zh-Hans")
        case .spanishLatinAmerica: Locale.Language(identifier: "es-419")
        case .french: Locale.Language(identifier: "fr")
        }
    }

    public var translationTarget: Locale.Language { Locale.Language(identifier: "en") }

    /// Whether the original line can be shown romanized (pinyin).
    public var supportsRomanization: Bool { self == .mandarin }

    /// Longest sentence (in characters) before splitting at a comma.
    public var softSentenceLimit: Int {
        switch self {
        case .mandarin: 36
        case .spanishLatinAmerica, .french: 110
        }
    }
}
