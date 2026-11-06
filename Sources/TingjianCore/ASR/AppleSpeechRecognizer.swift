import AVFoundation
import Speech

public enum RecognizerError: LocalizedError {
    case noCompatibleFormat
    case localeUnsupported(SourceLanguage)

    public var errorDescription: String? {
        switch self {
        case .noCompatibleFormat: "The speech model didn't report a usable audio format."
        case .localeUnsupported(let language): "\(language.displayName) speech recognition isn't supported on this Mac."
        }
    }
}

/// `SpeechAnalyzer` + `SpeechTranscriber` with volatile results.
public final class AppleSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
    public let language: SourceLanguage

    public init(language: SourceLanguage) {
        self.language = language
    }

    static func makeTranscriber(_ language: SourceLanguage) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: language.speechLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
    }

    public func prepare() async throws -> AVAudioFormat {
        guard await SpeechTranscriber.supportedLocale(equivalentTo: language.speechLocale) != nil else {
            throw RecognizerError.localeUnsupported(language)
        }
        try await FeasibilityReport.installSpeechAssetsIfNeeded(for: language)
        _ = try? await AssetInventory.reserve(locale: language.speechLocale)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [Self.makeTranscriber(language)]) else {
            throw RecognizerError.noCompatibleFormat
        }
        return format
    }

    public func transcribe(_ audio: AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<TranscriptUpdate, Error> {
        let language = self.language
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transcriber = Self.makeTranscriber(language)
                    let analyzer = SpeechAnalyzer(
                        modules: [transcriber],
                        options: .init(priority: .userInitiated, modelRetention: .processLifetime)
                    )
                    let (inputs, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
                    try await analyzer.start(inputSequence: inputs)

                    let results = Task {
                        for try await result in transcriber.results {
                            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                            continuation.yield(TranscriptUpdate(text: text, isFinal: result.isFinal))
                        }
                    }

                    for await buffer in audio {
                        if Task.isCancelled { break }
                        inputContinuation.yield(AnalyzerInput(buffer: buffer))
                    }
                    inputContinuation.finish()
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    try await results.value
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
