import AVFoundation
import Speech

public enum RecognizerError: LocalizedError {
    case noCompatibleFormat
    case localeUnsupported

    public var errorDescription: String? {
        switch self {
        case .noCompatibleFormat: "The speech model didn't report a usable audio format."
        case .localeUnsupported: "Mandarin (zh-CN) speech recognition isn't supported on this Mac."
        }
    }
}

/// `SpeechAnalyzer` + `SpeechTranscriber` (zh-CN) with volatile results.
public final class AppleSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
    public init() {}

    static func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(
            locale: Languages.speechLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
    }

    public func prepare() async throws -> AVAudioFormat {
        guard await SpeechTranscriber.supportedLocale(equivalentTo: Languages.speechLocale) != nil else {
            throw RecognizerError.localeUnsupported
        }
        try await FeasibilityReport.installSpeechAssetsIfNeeded()
        _ = try? await AssetInventory.reserve(locale: Languages.speechLocale)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [Self.makeTranscriber()]) else {
            throw RecognizerError.noCompatibleFormat
        }
        return format
    }

    public func transcribe(_ audio: AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<TranscriptUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transcriber = Self.makeTranscriber()
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
