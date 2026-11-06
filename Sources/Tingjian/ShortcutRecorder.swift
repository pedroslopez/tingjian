import AppKit
import SwiftUI

/// Click to record a new global shortcut. While recording: press the combo,
/// ⌫ to clear it (no hotkey), Esc to cancel. The ↺ button restores ⌥⌘T.
struct ShortcutRecorder: View {
    let model: AppModel
    @ViewState private var recording = false
    @ViewState private var hint: String?
    @ViewState private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(recording || model.shortcut == nil ? .secondary : .primary)
                    .frame(minWidth: 92)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.primary.opacity(recording ? 0.12 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(recording ? Color.accentColor : .clear, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .help(recording ? "Press a shortcut · ⌫ for none · Esc to cancel" : "Click to change")

            if model.shortcut != nil, !recording {
                Button {
                    model.shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("No hotkey")
            }
            if model.shortcut != .default, !recording {
                Button {
                    model.resetShortcut()
                } label: {
                    Image(systemName: "arrow.counterclockwise").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to \(Shortcut.default.display)")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if recording { return hint ?? "Type shortcut…" }
        return model.shortcut?.display ?? "None"
    }

    private func toggleRecording() {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard !recording else { return }
        recording = true
        hint = nil
        model.suspendHotKey(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Shortcut.record(event) {
            case .shortcut(let shortcut):
                stopRecording()
                model.shortcut = shortcut
            case .clear:
                stopRecording()
                model.shortcut = nil
            case .cancel:
                stopRecording()
            case .needsModifier:
                hint = "Add ⌘, ⌥ or ⌃"
            }
            return nil  // swallow the key while recording
        }
    }

    private func stopRecording() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        hint = nil
        model.suspendHotKey(false)
    }
}
