import Foundation
import Translation

public enum TranslatorError: LocalizedError {
    case notInstalled(SourceLanguage)
    case unsupported(SourceLanguage)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let language): "The \(language.displayName) → English translation model isn't downloaded. Add it in System Settings › General › Language & Region › Translation Languages."
        case .unsupported(let language): "\(language.displayName) → English translation isn't supported on this Mac."
        }
    }
}

/// `TranslationSession(installedSource:target:)` → English, high-fidelity strategy.
public final class AppleTranslator: Translator, @unchecked Sendable {
    public let language: SourceLanguage
    private let session: TranslationSession

    public init(language: SourceLanguage) {
        self.language = language
        session = TranslationSession(
            installedSource: language.translationSource,
            target: language.translationTarget,
            preferredStrategy: .highFidelity
        )
    }

    public func prepare() async throws {
        let status = await LanguageAvailability().status(from: language.translationSource, to: language.translationTarget)
        switch status {
        case .installed: break
        case .supported: throw TranslatorError.notInstalled(language)
        default: throw TranslatorError.unsupported(language)
        }
        _ = try await session.translate(warmUpPhrase)  // load the model
    }

    private var warmUpPhrase: String {
        switch language {
        case .mandarin: "你好"
        case .spanishLatinAmerica: "Hola"
        case .french: "Bonjour"
        }
    }

    public func translate(_ text: String) async throws -> String {
        try await session.translate(text).targetText
    }
}
