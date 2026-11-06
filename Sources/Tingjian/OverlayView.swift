import SwiftUI
import TingjianCore

/// Subtitle stack: small Chinese above large English, newest at the bottom,
/// older lines fading out, live lines dim until final.
struct OverlayView: View {
    let model: AppModel
    let state: OverlayState

    /// Hide the subtitles after this much silence.
    private let idleTimeout: TimeInterval = 7

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let lines = visibleLines
            let idle = isIdle(at: context.date)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                content(lines: lines, idle: idle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(lines: [Transcript.Line], idle: Bool) -> some View {
        let showCard = state.isInteractive || (!idle && (!lines.isEmpty || placeholder != nil))
        VStack(spacing: 10) {
            if lines.isEmpty || idle {
                if let placeholder {
                    StatusPill(text: placeholder, level: model.level)
                        .transition(.opacity)
                } else if state.isInteractive {
                    StatusPill(text: "Drag to move", level: 0)
                }
            } else {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    SubtitleLine(
                        line: line,
                        showChinese: model.showChinese,
                        textSize: model.textSize,
                        age: lines.count - 1 - index
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity.combined(with: .offset(y: -12))
                    ))
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.tint(.black.opacity(0.62)), in: .rect(cornerRadius: 22, style: .continuous))
                .overlay {
                    if state.isInteractive {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                }
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(showCard ? 1 : 0)
        .scaleEffect(showCard ? 1 : 0.97, anchor: .bottom)
        .animation(.smooth(duration: 0.35), value: lines.map(\.id))
        .animation(.easeInOut(duration: 0.6), value: showCard)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var visibleLines: [Transcript.Line] {
        let lines = model.transcript.lines
        return Array(lines.suffix(model.visibleLineCount))
    }

    private func isIdle(at date: Date) -> Bool {
        guard let last = model.transcript.lastActivity else { return true }
        return date.timeIntervalSince(last) > idleTimeout
    }

    private var placeholder: String? {
        switch model.status {
        case .preparing(let message): message
        case .listening where model.transcript.lastActivity == nil: model.hearingOnlySilence ? "Only silence so far…" : "Listening…"
        default: nil
        }
    }
}

private struct SubtitleLine: View {
    let line: Transcript.Line
    let showChinese: Bool
    let textSize: Double
    /// 0 = newest.
    let age: Int

    var body: some View {
        VStack(spacing: 3) {
            if showChinese {
                Text(line.chinese)
                    .font(.system(size: textSize * 0.6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(line.english.isEmpty ? "…" : line.english)
                .font(.system(size: textSize, weight: .semibold))
                .foregroundStyle(.white.opacity(line.isFinal ? 1 : 0.58))
                .lineLimit(2)
                .truncationMode(.head)
                .animation(.easeOut(duration: 0.25), value: line.english)
                .animation(.easeOut(duration: 0.3), value: line.isFinal)
        }
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .opacity(opacity)
        .scaleEffect(age == 0 ? 1 : 0.96)
        .frame(maxWidth: .infinity)
    }

    private var opacity: Double {
        switch age {
        case 0: 1
        case 1: 0.6
        default: 0.38
        }
    }
}

private struct StatusPill: View {
    let text: String
    let level: Float

    var body: some View {
        HStack(spacing: 8) {
            LevelBars(level: level)
                .frame(width: 16, height: 14)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct LevelBars: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { i in
                    let wave = (sin(t * 5 + Double(i) * 1.3) + 1) / 2
                    let height = 0.25 + 0.75 * min(1, Double(level) * (0.6 + 0.4 * wave) + 0.12 * wave)
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 2.5)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: height)
                }
            }
        }
    }
}
