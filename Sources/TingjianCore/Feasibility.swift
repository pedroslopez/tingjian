import AVFoundation
import Foundation
import Speech
import Translation

/// Checks that the on-device models tingjian relies on are available.
public struct FeasibilityReport: Sendable, CustomStringConvertible {
    public enum TranslationStatus: String, Sendable { case installed, supported, unsupported }

    public var language: SourceLanguage
    public var transcriberAvailable: Bool
    public var speechLocaleSupported: Bool
    public var speechLocaleInstalled: Bool
    public var speechAssetStatus: String
    public var translationStatus: TranslationStatus
    public var analyzerFormat: String?

    public var isReady: Bool {
        transcriberAvailable && speechLocaleInstalled && translationStatus == .installed
    }

    public var description: String {
        """
        Language                             \(language.displayName)
        SpeechTranscriber.isAvailable        \(transcriberAvailable)
        \(pad(tag + " in supportedLocales"))\(speechLocaleSupported)
        \(pad(tag + " in installedLocales"))\(speechLocaleInstalled)
        \(pad(tag + " asset status"))\(speechAssetStatus)
        \(pad("Translation " + language.translationSource.minimalIdentifier + " → en"))\(translationStatus.rawValue)
        Analyzer audio format                \(analyzerFormat ?? "n/a")
        Ready                                \(isReady)
        """
    }

    private var tag: String { language.speechLocale.identifier(.bcp47) }

    private func pad(_ s: String) -> String {
        s.padding(toLength: max(37, s.count + 1), withPad: " ", startingAt: 0)
    }

    public static func run(language: SourceLanguage = .mandarin) async -> FeasibilityReport {
        let locale = language.speechLocale
        let tag = locale.identifier(.bcp47)
        let supported = await SpeechTranscriber.supportedLocales.contains { $0.identifier(.bcp47) == tag }
        let installed = await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == tag }
        let transcriber = AppleSpeechRecognizer.makeTranscriber(language)
        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let availability = LanguageAvailability()
        let status = await availability.status(from: language.translationSource, to: language.translationTarget)
        let translation: TranslationStatus = switch status {
        case .installed: .installed
        case .supported: .supported
        default: .unsupported
        }

        return FeasibilityReport(
            language: language,
            transcriberAvailable: SpeechTranscriber.isAvailable,
            speechLocaleSupported: supported,
            speechLocaleInstalled: installed,
            speechAssetStatus: String(describing: assetStatus),
            translationStatus: translation,
            analyzerFormat: format.map { "\(Int($0.sampleRate)) Hz, \($0.channelCount) ch, \($0.commonFormat == .pcmFormatInt16 ? "Int16" : "\($0.commonFormat.rawValue)")" }
        )
    }

    /// Downloads the language's speech model if it isn't installed yet.
    public static func installSpeechAssetsIfNeeded(for language: SourceLanguage, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let transcriber = AppleSpeechRecognizer.makeTranscriber(language)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        let observation = progress.map { cb in
            request.progress.observe(\.fractionCompleted) { p, _ in cb(p.fractionCompleted) }
        }
        defer { observation?.invalidate() }
        try await request.downloadAndInstall()
    }
}
