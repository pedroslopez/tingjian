import Foundation
import Observation

/// The running bilingual transcript.
///
/// Recognizer updates are split into sentences; each sentence is a `Line`.
/// A source's volatile text maps onto a run of live lines that are reconciled
/// in place on every update. Live lines are translated on a throttle; when the
/// recognizer finalizes, the lines are committed and translated definitively.
@MainActor
@Observable
public final class Transcript {
    public struct Line: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let source: SourceKind
        public let startedAt: Date
        public var original: String
        public var english: String
        /// The recognizer committed the original text.
        public var isCommitted: Bool
        /// Committed and the definitive translation has arrived.
        public var isFinal: Bool
    }

    public private(set) var lines: [Line] = []
    /// Last time any text arrived; the overlay uses it to fade out when idle.
    public private(set) var lastActivity: Date?
    /// Most recent translation failure, surfaced in the UI.
    public private(set) var translationError: String?

    @ObservationIgnored public var maxLines = 400
    @ObservationIgnored public var partialInterval: Duration = .milliseconds(250)
    /// Called whenever a line changes (for logging / the CLI).
    @ObservationIgnored public var onLineChange: ((Line) -> Void)?

    @ObservationIgnored private var translator: Translator
    @ObservationIgnored public var softSentenceLimit: Int
    /// Live line ids per source, in order; the last one is the growing tail.
    @ObservationIgnored private var live: [SourceKind: [UUID]] = [:]
    @ObservationIgnored private var partials: [UUID: PartialState] = [:]
    @ObservationIgnored private var cache = TranslationCache()

    private struct PartialState {
        var scheduled = false
        var inFlight = false
        var dirty = false
    }

    public init(translator: Translator, softSentenceLimit: Int = 36) {
        self.translator = translator
        self.softSentenceLimit = softSentenceLimit
    }

    /// Switches language. Keeps finished lines; drops anything in flight.
    public func reconfigure(translator: Translator, softSentenceLimit: Int) {
        self.translator = translator
        self.softSentenceLimit = softSentenceLimit
        let open = Set(live.values.flatMap { $0 })
        lines.removeAll { open.contains($0.id) }
        live.removeAll()
        partials.removeAll()
        cache = TranslationCache()
    }

    public var finalLines: [Line] { lines.filter(\.isFinal) }

    public func clear() {
        lines.removeAll()
        live.removeAll()
        partials.removeAll()
        lastActivity = nil
    }

    // MARK: - Recognizer input

    public func apply(_ update: TranscriptUpdate, from source: SourceKind) {
        let sentences = Segmenter.sentences(update.text, softLimit: softSentenceLimit)
        var ids = live[source] ?? []

        // Reconcile sentences onto the existing live lines.
        var changed: [UUID] = []
        for (k, sentence) in sentences.enumerated() {
            if k < ids.count {
                guard let i = index(of: ids[k]) else { continue }
                if lines[i].original != sentence {
                    lines[i].original = sentence
                    if let cached = cache[sentence] { lines[i].english = cached }
                    changed.append(ids[k])
                }
            } else {
                ids.append(newLine(for: source, original: sentence))
                changed.append(ids.last!)
            }
        }
        if ids.count > sentences.count {
            let dropped = Set(ids[sentences.count...])
            lines.removeAll { dropped.contains($0.id) }
            dropped.forEach { partials[$0] = nil }
            ids.removeLast(ids.count - sentences.count)
        }
        if !sentences.isEmpty { lastActivity = .now }

        if update.isFinal {
            live[source] = nil
            for id in ids {
                partials[id] = nil
                guard let i = index(of: id) else { continue }
                lines[i].isCommitted = true
                notify(i)
                let text = lines[i].original
                Task { await translateFinal(id: id, text: text) }
            }
        } else {
            live[source] = ids
            for id in changed {
                if let i = index(of: id) { notify(i) }
                schedulePartial(id)
            }
        }
    }

    /// Finalizes any open live lines (e.g. on stop when the recognizer was cut off).
    public func commitLiveLines() {
        for (source, ids) in live {
            live[source] = nil
            for id in ids {
                partials[id] = nil
                guard let i = index(of: id) else { continue }
                lines[i].isCommitted = true
                let text = lines[i].original
                Task { await translateFinal(id: id, text: text) }
            }
        }
    }

    // MARK: - Translation

    private func translate(_ text: String) async throws -> String {
        if let cached = cache[text] { return cached }
        let english = try await translator.translate(text)
        cache[text] = english
        return english
    }

    private func translateFinal(id: UUID, text: String) async {
        var english: String?
        do {
            english = try await translate(text)
            translationError = nil
        } catch {
            translationError = error.localizedDescription
        }
        guard let i = index(of: id) else { return }
        if let english { lines[i].english = english }
        lines[i].isFinal = true
        lastActivity = .now
        notify(i)
    }

    /// Throttled: at most one partial translation in flight per line, started
    /// `partialInterval` after the first change, always using the latest text.
    private func schedulePartial(_ id: UUID) {
        var state = partials[id] ?? PartialState()
        defer { partials[id] = state }
        if state.inFlight { state.dirty = true; return }
        if state.scheduled { return }
        state.scheduled = true
        // Cached sentences resolve instantly; no need to wait.
        let delay = index(of: id).flatMap { cache[lines[$0].original] } != nil ? .zero : partialInterval
        Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            await runPartial(id)
        }
    }

    private func runPartial(_ id: UUID) async {
        guard var state = partials[id], let i = index(of: id), !lines[i].isCommitted else { return }
        state.scheduled = false
        state.inFlight = true
        state.dirty = false
        partials[id] = state

        let text = lines[i].original
        let english = try? await translate(text)

        guard partials[id] != nil, let j = index(of: id), !lines[j].isCommitted else { return }
        if let english, lines[j].english != english {
            lines[j].english = english
            notify(j)
        }
        partials[id]?.inFlight = false
        if partials[id]?.dirty == true {
            partials[id]?.dirty = false
            schedulePartial(id)
        }
    }

    // MARK: - Helpers

    private func newLine(for source: SourceKind, original: String) -> UUID {
        let line = Line(id: UUID(), source: source, startedAt: .now, original: original,
                        english: cache[original] ?? "", isCommitted: false, isFinal: false)
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        return line.id
    }

    private func index(of id: UUID) -> Int? {
        lines.lastIndex { $0.id == id }
    }

    private func notify(_ i: Int) {
        onLineChange?(lines[i])
    }
}

/// Small bounded cache so settled sentences aren't re-translated on every update.
struct TranslationCache {
    private var storage: [String: String] = [:]
    private var order: [String] = []
    var capacity = 512

    subscript(key: String) -> String? {
        get { storage[key] }
        set {
            guard let newValue else { return }
            if storage.updateValue(newValue, forKey: key) == nil {
                order.append(key)
                if order.count > capacity { storage[order.removeFirst()] = nil }
            }
        }
    }
}
