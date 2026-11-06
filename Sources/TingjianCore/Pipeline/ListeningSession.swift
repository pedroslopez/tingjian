import AVFoundation
import Foundation

/// Wires audio sources → format conversion → recognizer (one per source) → transcript.
@MainActor
public final class ListeningSession {
    public let transcript: Transcript
    private let sources: [AudioSource]
    private let makeRecognizer: () -> SpeechRecognizer
    private var tasks: [Task<Void, Never>] = []
    /// Reports recognizer errors (e.g. a source dying).
    public var onError: ((Error) -> Void)?

    public init(sources: [AudioSource], transcript: Transcript, makeRecognizer: @escaping () -> SpeechRecognizer) {
        self.sources = sources
        self.transcript = transcript
        self.makeRecognizer = makeRecognizer
    }

    public func start() async throws {
        await stop()
        do {
            for source in sources {
                let recognizer = makeRecognizer()
                let format = try await recognizer.prepare()
                let raw = try await source.start()
                let converted = Self.convert(raw, to: format)
                let updates = recognizer.transcribe(converted)
                let kind = source.kind
                tasks.append(Task { [weak self] in
                    do {
                        for try await update in updates {
                            self?.transcript.apply(update, from: kind)
                        }
                    } catch {
                        self?.onError?(error)
                    }
                })
            }
        } catch {
            await stop()
            throw error
        }
    }

    /// Stops capture and waits for the recognizers to flush their last results.
    public func stop() async {
        sources.forEach { $0.stop() }
        let running = tasks
        tasks.removeAll()
        for task in running { await task.value }
        transcript.commitLiveLines()
    }

    nonisolated static func convert(_ input: AsyncStream<AVAudioPCMBuffer>, to format: AVAudioFormat) -> AsyncStream<AVAudioPCMBuffer> {
        let (output, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self, bufferingPolicy: .bufferingNewest(512))
        let task = Task.detached(priority: .userInitiated) {
            let converter = BufferConverter(outputFormat: format)
            for await buffer in input {
                if let converted = converter.convert(buffer) { continuation.yield(converted) }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return output
    }
}
