import AVFoundation

/// One recognition update. Volatile (non-final) updates replace the previous
/// volatile text for the same source; a final update commits it.
public struct TranscriptUpdate: Sendable, Equatable {
    public var text: String
    public var isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// Streaming speech recognizer. Implementations: Apple SpeechAnalyzer (default);
/// sherpa-onnx streaming Paraformer or WhisperKit could slot in here.
public protocol SpeechRecognizer: AnyObject, Sendable {
    /// Makes sure models are installed and returns the audio format `transcribe` expects.
    func prepare() async throws -> AVAudioFormat

    /// Transcribes `audio` (already in the prepared format). The returned stream
    /// finishes after `audio` finishes and the recognizer has flushed.
    func transcribe(_ audio: AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<TranscriptUpdate, Error>
}
