import AVFoundation

public enum SourceKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case microphone

    public var id: String { rawValue }
}

/// A live audio input. Buffers come out in the source's native format; the
/// pipeline converts them for the recognizer.
public protocol AudioSource: AnyObject {
    var kind: SourceKind { get }
    func start() async throws -> AsyncStream<AVAudioPCMBuffer>
    func stop()
}

public struct CoreAudioError: LocalizedError {
    public var operation: String
    public var status: OSStatus

    public var errorDescription: String? { "\(operation) failed (OSStatus \(status))" }
}

@inline(__always)
func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation(), status: status) }
}

extension AVAudioPCMBuffer {
    /// Deep copy, so the buffer outlives the render callback that produced it.
    func copied() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (s, d) in zip(src, dst) {
            guard let sData = s.mData, let dData = d.mData else { continue }
            memcpy(dData, sData, Int(min(s.mDataByteSize, d.mDataByteSize)))
        }
        return copy
    }
}
