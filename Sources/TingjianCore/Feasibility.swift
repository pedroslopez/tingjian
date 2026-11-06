import AVFoundation
import Foundation
import Speech
import Translation

/// Checks that the on-device models tingjian relies on are available.
public struct FeasibilityReport: Sendable, CustomStringConvertible {
    public enum TranslationStatus: String, Sendable { case installed, supported, unsupported }

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
        SpeechTranscriber.isAvailable        \(transcriberAvailable)
        zh-CN in supportedLocales            \(speechLocaleSupported)
        zh-CN in installedLocales            \(speechLocaleInstalled)
        zh-CN asset status                   \(speechAssetStatus)
        Translation zh-Hans → en             \(translationStatus.rawValue)
        Analyzer audio format                \(analyzerFormat ?? "n/a")
        Ready                                \(isReady)
        """
    }

    public static func run() async -> FeasibilityReport {
        let locale = Languages.speechLocale
        let tag = locale.identifier(.bcp47)
        let supported = await SpeechTranscriber.supportedLocales.contains { $0.identifier(.bcp47) == tag }
        let installed = await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == tag }
        let transcriber = AppleSpeechRecognizer.makeTranscriber()
        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let availability = LanguageAvailability()
        let status = await availability.status(from: Languages.translationSource, to: Languages.translationTarget)
        let translation: TranslationStatus = switch status {
        case .installed: .installed
        case .supported: .supported
        default: .unsupported
        }

        return FeasibilityReport(
            transcriberAvailable: SpeechTranscriber.isAvailable,
            speechLocaleSupported: supported,
            speechLocaleInstalled: installed,
            speechAssetStatus: String(describing: assetStatus),
            translationStatus: translation,
            analyzerFormat: format.map { "\(Int($0.sampleRate)) Hz, \($0.channelCount) ch, \($0.commonFormat == .pcmFormatInt16 ? "Int16" : "\($0.commonFormat.rawValue)")" }
        )
    }

    /// Downloads the zh-CN speech model if it isn't installed yet.
    public static func installSpeechAssetsIfNeeded(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let transcriber = AppleSpeechRecognizer.makeTranscriber()
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        let observation = progress.map { cb in
            request.progress.observe(\.fractionCompleted) { p, _ in cb(p.fractionCompleted) }
        }
        defer { observation?.invalidate() }
        try await request.downloadAndInstall()
    }
}
