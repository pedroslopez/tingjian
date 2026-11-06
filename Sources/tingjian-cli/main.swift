import AVFoundation
import Foundation
import TingjianCore

// tingjian-cli: feasibility check + headless pipeline runs.
//
//   tingjian-cli check              model / language availability
//   tingjian-cli install            download the zh-CN speech model
//   tingjian-cli file <audio>       run a file through ASR + translation (real time)
//   tingjian-cli tap [seconds]      capture system audio via the process tap
//   tingjian-cli mic [seconds]      capture the microphone

let args = CommandLine.arguments.dropFirst()
let start = Date()

func stamp() -> String { String(format: "%6.2fs", Date().timeIntervalSince(start)) }

@MainActor
func run(sources: [AudioSource], seconds: Double) async throws {
    let translator = AppleTranslator()
    print("[\(stamp())] preparing translator…")
    try await translator.prepare()
    let transcript = Transcript(translator: translator)
    transcript.onLineChange = { line in
        let tag = line.isFinal ? "FINAL" : line.isCommitted ? "COMMIT" : "live "
        print("[\(stamp())] \(tag) [\(line.source.rawValue)] \(line.chinese)  →  \(line.english)")
    }
    let session = ListeningSession(sources: sources, transcript: transcript) { AppleSpeechRecognizer() }
    session.onError = { print("[\(stamp())] error: \($0)") }
    try await session.start()
    print("[\(stamp())] listening for \(seconds)s…")
    try await Task.sleep(for: .seconds(seconds))
    await session.stop()
    try await Task.sleep(for: .seconds(2))  // let final translations land
    print("--- transcript ---")
    for line in transcript.finalLines { print("\(line.chinese)\n  \(line.english)") }
}

do {
    switch args.first {
    case "check", nil:
        let report = await FeasibilityReport.run()
        print(report)
        exit(report.isReady ? 0 : 1)
    case "install":
        try await FeasibilityReport.installSpeechAssetsIfNeeded { print(String(format: "%.0f%%", $0 * 100)) }
        print(await FeasibilityReport.run())
    case "file":
        guard let path = args.dropFirst().first else { print("usage: file <audio>"); exit(2) }
        let url = URL(fileURLWithPath: path)
        let duration = try AVAudioFile(forReading: url).duration
        try await run(sources: [AudioFileSource(url: url)], seconds: duration + 3)
    case "tap":
        try await run(sources: [SystemAudioTap()], seconds: Double(args.dropFirst().first ?? "") ?? 20)
    case "mic":
        try await run(sources: [MicrophoneSource()], seconds: Double(args.dropFirst().first ?? "") ?? 20)
    default:
        print("unknown command \(args.first!)")
        exit(2)
    }
} catch {
    print("error: \(error.localizedDescription)")
    exit(1)
}

extension AVAudioFile {
    var duration: Double { Double(length) / fileFormat.sampleRate }
}
