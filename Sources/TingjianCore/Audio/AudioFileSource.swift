import AVFoundation

/// Plays a file into the pipeline (for testing without the tap).
public final class AudioFileSource: AudioSource {
    public let kind = SourceKind.system
    private let url: URL
    private let realtime: Bool
    private var task: Task<Void, Never>?

    public init(url: URL, realtime: Bool = true) {
        self.url = url
        self.realtime = realtime
    }

    public func start() async throws -> AsyncStream<AVAudioPCMBuffer> {
        let file = try AVAudioFile(forReading: url)
        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        let realtime = self.realtime
        task = Task.detached {
            let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)  // 100 ms
            while !Task.isCancelled {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
                      (try? file.read(into: buffer, frameCount: chunk)) != nil, buffer.frameLength > 0 else { break }
                continuation.yield(buffer)
                if realtime { try? await Task.sleep(for: .milliseconds(100)) }
            }
            continuation.finish()
        }
        return stream
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
