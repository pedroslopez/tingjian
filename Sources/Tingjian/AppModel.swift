import AppKit
import Observation
import OSLog
import SwiftUI
import TingjianCore

enum SourceMode: String, CaseIterable, Identifiable {
    case system, microphone, both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .microphone: "Mic"
        case .both: "Both"
        }
    }

    var kinds: [SourceKind] {
        switch self {
        case .system: [.system]
        case .microphone: [.microphone]
        case .both: [.system, .microphone]
        }
    }
}

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case idle
        case preparing(String)
        case listening
        case failed(String)
    }

    // MARK: State

    private(set) var status: Status = .idle
    /// Smoothed input level (0…1) across sources, for the menu bar icon.
    private(set) var level: Float = 0
    /// True when we've been listening for a while and every buffer was silent:
    /// usually means the audio-capture permission is off.
    private(set) var hearingOnlySilence = false
    let transcript: Transcript

    var isListening: Bool { status == .listening }
    var isBusy: Bool { if case .preparing = status { true } else { false } }

    // MARK: Settings (persisted)

    var sourceMode: SourceMode {
        didSet {
            defaults.set(sourceMode.rawValue, forKey: Keys.sourceMode)
            if sourceMode != oldValue, isListening { Task { await restart() } }
        }
    }
    var showChinese: Bool { didSet { defaults.set(showChinese, forKey: Keys.showChinese) } }
    var textSize: Double { didSet { defaults.set(textSize, forKey: Keys.textSize) } }
    var visibleLineCount: Int { didSet { defaults.set(visibleLineCount, forKey: Keys.visibleLineCount) } }

    // MARK: Private

    private let defaults = UserDefaults.standard
    private let translator: Translator
    private var session: ListeningSession?
    private var translatorReady = false
    private var startedAt: Date?
    private var loudestSinceStart: Float = 0

    private enum Keys {
        static let sourceMode = "sourceMode"
        static let showChinese = "showChinese"
        static let textSize = "textSize"
        static let visibleLineCount = "visibleLineCount"
    }

    init(translator: Translator = AppleTranslator()) {
        self.translator = translator
        transcript = Transcript(translator: translator)
        sourceMode = SourceMode(rawValue: defaults.string(forKey: Keys.sourceMode) ?? "") ?? .system
        showChinese = defaults.object(forKey: Keys.showChinese) as? Bool ?? true
        textSize = defaults.object(forKey: Keys.textSize) as? Double ?? 26
        visibleLineCount = defaults.object(forKey: Keys.visibleLineCount) as? Int ?? 3
        transcript.onLineChange = { line in
            guard line.isFinal else { return }
            Self.log.info("[\(line.source.rawValue, privacy: .public)] \(line.chinese, privacy: .public) → \(line.english, privacy: .public)")
        }
    }

    static let log = Logger(subsystem: "com.pedroslopez.tingjian", category: "transcript")

    // MARK: Listening

    func toggle() {
        Task {
            if isListening || isBusy { await stop() } else { await start() }
        }
    }

    func start() async {
        guard !isListening, !isBusy else { return }
        status = .preparing("Loading models…")
        do {
            if !translatorReady {
                try await translator.prepare()
                translatorReady = true
            }
            if !(await FeasibilityReport.run().speechLocaleInstalled) {
                status = .preparing("Downloading Mandarin speech model…")
                try await FeasibilityReport.installSpeechAssetsIfNeeded { [weak self] fraction in
                    Task { @MainActor in
                        self?.status = .preparing("Downloading Mandarin speech model… \(Int(fraction * 100))%")
                    }
                }
            }

            let sources: [AudioSource] = sourceMode.kinds.map { kind in
                switch kind {
                case .system: SystemAudioTap()
                case .microphone: MicrophoneSource()
                }
            }
            let session = ListeningSession(sources: sources, transcript: transcript) { AppleSpeechRecognizer() }
            session.onLevel = { [weak self] _, rms in self?.receiveLevel(rms) }
            session.onError = { [weak self] error in
                guard let self else { return }
                self.status = .failed(error.localizedDescription)
                Task { await self.stop(keepStatus: true) }
            }
            try await session.start()
            self.session = session
            startedAt = .now
            loudestSinceStart = 0
            hearingOnlySilence = false
            status = .listening
            Self.log.info("listening (\(self.sourceMode.rawValue, privacy: .public))")
        } catch {
            Self.log.error("start failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    func stop(keepStatus: Bool = false) async {
        let session = self.session
        self.session = nil
        if !keepStatus { status = .idle }
        await session?.stop()
        level = 0
        hearingOnlySilence = false
    }

    private func restart() async {
        await stop()
        await start()
    }

    private func receiveLevel(_ rms: Float) {
        // Map RMS to a perceptual 0…1 range (-50 dB … -10 dB).
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = Float(min(max((db + 50) / 40, 0), 1))
        level = max(normalized, level * 0.8)
        loudestSinceStart = max(loudestSinceStart, rms)
        if let startedAt, Date.now.timeIntervalSince(startedAt) > 12 {
            hearingOnlySilence = loudestSinceStart == 0 && sourceMode != .microphone
        }
    }

    // MARK: History

    func copyAll() {
        let text = transcript.finalLines
            .map { "\($0.chinese)\n\($0.english)" }
            .joined(separator: "\n\n")
        copy(text)
    }

    func copy(_ line: Transcript.Line) {
        copy("\(line.chinese)\n\(line.english)")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func openAudioCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
