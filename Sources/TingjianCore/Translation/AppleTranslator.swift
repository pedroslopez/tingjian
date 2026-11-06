import Foundation
import Translation

public enum TranslatorError: LocalizedError {
    case notInstalled
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .notInstalled: "The Chinese → English translation model isn't downloaded. Add it in System Settings › General › Language & Region › Translation Languages."
        case .unsupported: "Chinese → English translation isn't supported on this Mac."
        }
    }
}

/// `TranslationSession(installedSource:target:)` zh-Hans → en, high-fidelity strategy.
public final class AppleTranslator: Translator, @unchecked Sendable {
    private let session: TranslationSession

    public init() {
        session = TranslationSession(
            installedSource: Languages.translationSource,
            target: Languages.translationTarget,
            preferredStrategy: .highFidelity
        )
    }

    public func prepare() async throws {
        let status = await LanguageAvailability().status(from: Languages.translationSource, to: Languages.translationTarget)
        switch status {
        case .installed: break
        case .supported: throw TranslatorError.notInstalled
        default: throw TranslatorError.unsupported
        }
        _ = try await session.translate("你好")  // warm up the model
    }

    public func translate(_ text: String) async throws -> String {
        try await session.translate(text).targetText
    }
}
