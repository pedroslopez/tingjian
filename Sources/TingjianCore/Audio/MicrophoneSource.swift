import AVFoundation

/// Default input device via `AVAudioEngine`.
public final class MicrophoneSource: AudioSource {
    public let kind = SourceKind.microphone
    private var engine: AVAudioEngine?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    public init() {}

    public func start() async throws -> AsyncStream<AVAudioPCMBuffer> {
        stop()
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw MicrophoneError.denied
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self, bufferingPolicy: .bufferingNewest(256))
        self.continuation = continuation

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            if let copy = buffer.copied() { continuation.yield(copy) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            throw error
        }
        self.engine = engine
        return stream
    }

    public func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        continuation?.finish()
        continuation = nil
    }
}

public enum MicrophoneError: LocalizedError {
    case denied
    public var errorDescription: String? {
        "Microphone access is off. Enable tingjian in System Settings › Privacy & Security › Microphone."
    }
}
