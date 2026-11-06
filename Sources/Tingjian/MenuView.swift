import SwiftUI
import TingjianCore

struct MenuView: View {
    @Bindable var model: AppModel
    let overlay: OverlayController
    @ViewState private var copiedLine: UUID?
    @ViewState private var copiedAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            listenButton
            if let message = statusMessage {
                message
            }
            Divider()
            settings
            Divider()
            history
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("听见").font(.system(size: 17, weight: .semibold))
            Text("tingjian").font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .idle: .secondary.opacity(0.5)
        case .preparing: .orange
        case .listening: .green
        case .failed: .red
        }
    }

    private var statusText: String {
        switch model.status {
        case .idle: "Idle"
        case .preparing: "Starting"
        case .listening: "Listening"
        case .failed: "Error"
        }
    }

    private var listenButton: some View {
        Button {
            model.toggle()
        } label: {
            HStack {
                Image(systemName: model.isListening || model.isBusy ? "stop.fill" : "play.fill")
                Text(model.isListening ? "Stop listening" : model.isBusy ? "Cancel" : "Start listening")
                Spacer()
                Text("⌥⌘T").font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(model.isListening ? .red.opacity(0.85) : .accentColor)
        .controlSize(.large)
    }

    @ViewBuilder
    private var statusMessage: (some View)? {
        switch model.status {
        case .preparing(let message):
            Label(message, systemImage: "arrow.down.circle")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .listening where model.hearingOnlySilence:
            VStack(alignment: .leading, spacing: 4) {
                Label("Only silence so far. If something is playing, allow tingjian under System Audio Recording.", systemImage: "speaker.slash")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings…") { model.openAudioCaptureSettings() }
                    .buttonStyle(.link).font(.system(size: 11))
            }
        default:
            if let error = model.transcript.translationError {
                Label(error, systemImage: "character.bubble")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Listen to")
                Spacer()
                Picker("Listen to", selection: $model.sourceMode) {
                    ForEach(SourceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            Toggle("Show Chinese", isOn: $model.showChinese)
                .toggleStyle(.switch).controlSize(.small)
            HStack {
                Text("Lines")
                Spacer()
                Picker("Lines", selection: $model.visibleLineCount) {
                    Text("1").tag(1); Text("2").tag(2); Text("3").tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
            }
            HStack(spacing: 8) {
                Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                Slider(value: $model.textSize, in: 16...44)
                Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
    }

    // MARK: History

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History").font(.system(size: 12, weight: .semibold))
                Spacer()
                if !model.transcript.finalLines.isEmpty {
                    Button(copiedAll ? "Copied" : "Copy all") {
                        model.copyAll()
                        flash($copiedAll)
                    }
                    .buttonStyle(.link).font(.system(size: 11))
                    Button("Clear") { model.transcript.clear() }
                        .buttonStyle(.link).font(.system(size: 11))
                }
            }
            let lines = Array(model.transcript.finalLines.suffix(50).reversed())
            if lines.isEmpty {
                Text("Translations from this session appear here.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            HistoryRow(line: line, copied: copiedLine == line.id) {
                                model.copy(line)
                                copiedLine = line.id
                                Task {
                                    try? await Task.sleep(for: .seconds(1.2))
                                    if copiedLine == line.id { copiedLine = nil }
                                }
                            }
                        }
                    }
                }
                .frame(height: min(240, CGFloat(lines.count) * 52))
                .scrollIndicators(.automatic)
            }
        }
    }

    private func flash(_ flag: Binding<Bool>) {
        flag.wrappedValue = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            flag.wrappedValue = false
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Reset overlay position") { overlay.resetPosition() }
                .buttonStyle(.link)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.link)
                .keyboardShortcut("q")
        }
        .font(.system(size: 11))
    }
}

private struct HistoryRow: View {
    let line: Transcript.Line
    let copied: Bool
    let copy: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: copy) {
            HStack(alignment: .top, spacing: 8) {
                if line.source == .microphone {
                    Image(systemName: "mic.fill").font(.system(size: 9)).foregroundStyle(.secondary).padding(.top, 3)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.english).font(.system(size: 12)).foregroundStyle(.primary)
                    Text(line.chinese).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(copied ? .green : .secondary)
                    .opacity(hovering || copied ? 1 : 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(hovering ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Click to copy")
    }
}
