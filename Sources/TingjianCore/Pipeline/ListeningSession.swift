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
    /// Audio level (RMS, 0…1) per source, about 12 times a second.
    public var onLevel: (@MainActor (SourceKind, Float) -> Void)?

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
                let kindForLevel = source.kind
                let onLevel = self.onLevel
                let converted = Self.convert(raw, to: format) { level in
                    Task { @MainActor in onLevel?(kindForLevel, level) }
                }
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

    nonisolated static func convert(
        _ input: AsyncStream<AVAudioPCMBuffer>,
        to format: AVAudioFormat,
        level: @escaping @Sendable (Float) -> Void
    ) -> AsyncStream<AVAudioPCMBuffer> {
        let (output, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self, bufferingPolicy: .bufferingNewest(512))
        let task = Task.detached(priority: .userInitiated) {
            let converter = BufferConverter(outputFormat: format)
            var meter = LevelMeter(sampleRate: format.sampleRate)
            for await buffer in input {
                guard let converted = converter.convert(buffer) else { continue }
                continuation.yield(converted)
                if let rms = meter.add(converted) { level(rms) }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return output
    }
}

/// Accumulates RMS over ~80 ms windows of Int16 / Float32 mono audio.
struct LevelMeter {
    private let window: Int
    private var sum: Double = 0
    private var count = 0

    init(sampleRate: Double) {
        window = Int(sampleRate * 0.08)
    }

    mutating func add(_ buffer: AVAudioPCMBuffer) -> Float? {
        let n = Int(buffer.frameLength)
        if let samples = buffer.int16ChannelData?[0] {
            for i in 0..<n { let v = Double(samples[i]) / 32768; sum += v * v }
        } else if let samples = buffer.floatChannelData?[0] {
            for i in 0..<n { let v = Double(samples[i]); sum += v * v }
        } else {
            return nil
        }
        count += n
        guard count >= window else { return nil }
        let rms = Float((sum / Double(count)).squareRoot())
        sum = 0
        count = 0
        return rms
    }
}
