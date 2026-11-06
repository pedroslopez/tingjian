import AVFoundation
import CoreAudio

/// Captures everything the Mac is playing via a Core Audio process tap
/// (`CATapDescription`) wrapped in a private aggregate device.
///
/// Needs the "System Audio Recording" permission (NSAudioCaptureUsageDescription);
/// without it the tap delivers silence.
public final class SystemAudioTap: AudioSource {
    public let kind = SourceKind.system

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private let queue = DispatchQueue(label: "tingjian.system-tap", qos: .userInteractive)
    private var deviceListener: AudioObjectPropertyListenerBlock?

    public init() {}

    public func start() async throws -> AsyncStream<AVAudioPCMBuffer> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self, bufferingPolicy: .bufferingNewest(256))
        self.continuation = continuation
        do {
            try startTap()
            watchDefaultOutputDevice()
        } catch {
            stop()
            throw error
        }
        return stream
    }

    public func stop() {
        unwatchDefaultOutputDevice()
        teardownTap()
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Tap lifecycle

    private func startTap() throws {
        // Global stereo mixdown of every process. We never play audio ourselves.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "tingjian"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "AudioHardwareCreateProcessTap")
        tapID = tap

        var asbd = AudioStreamBasicDescription()
        try getProperty(tap, kAudioTapPropertyFormat, &asbd)
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw CoreAudioError(operation: "Reading tap format", status: -1)
        }

        let outputUID = try Self.defaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "tingjian system tap",
            kAudioAggregateDeviceUIDKey: "com.pedroslopez.tingjian.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var aggregateDevice = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateDevice), "AudioHardwareCreateAggregateDevice")
        aggregateID = aggregateDevice

        // The tap's buffers are the last ones in the aggregate's input list
        // (an output device with a mic, e.g. a headset, adds its own first).
        let tapBufferCount = format.isInterleaved ? 1 : Int(format.channelCount)
        let continuation = self.continuation

        var proc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateDevice, queue) { _, inputData, _, _, _ in
            let all = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            guard all.count >= tapBufferCount else { return }
            let frameBytes = Int(format.streamDescription.pointee.mBytesPerFrame)
            guard frameBytes > 0 else { return }
            let frames = AVAudioFrameCount(Int(all[all.count - tapBufferCount].mDataByteSize) / frameBytes)
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
            buffer.frameLength = frames
            let dst = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            for i in 0..<tapBufferCount {
                let src = all[all.count - tapBufferCount + i]
                guard let s = src.mData, let d = dst[i].mData else { continue }
                memcpy(d, s, Int(min(src.mDataByteSize, dst[i].mDataByteSize)))
            }
            continuation?.yield(buffer)
        }, "AudioDeviceCreateIOProcIDWithBlock")
        procID = proc

        try check(AudioDeviceStart(aggregateDevice, proc), "AudioDeviceStart")
    }

    private func teardownTap() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Follow the default output device (e.g. plugging in headphones)

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private func watchDefaultOutputDevice() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.continuation != nil else { return }
            self.teardownTap()
            try? self.startTap()
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, queue, listener)
    }

    private func unwatchDefaultOutputDevice() {
        guard let deviceListener else { return }
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, queue, deviceListener)
        self.deviceListener = nil
    }

    // MARK: - Helpers

    private func getProperty<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) throws {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "AudioObjectGetPropertyData(\(selector))")
    }

    static func defaultOutputDeviceUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, 0, nil, &size, &device), "default output device")

        var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &size, &uid), "output device UID")
        guard let uid else { throw CoreAudioError(operation: "output device UID", status: -1) }
        return uid.takeRetainedValue() as String
    }
}
