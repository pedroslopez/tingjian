# tingjian 听见

A personal macOS menu bar app that listens to everything (system audio, plus the mic if enabled) and shows live **Mandarin → English** translation in a sleek floating overlay. Everything runs **locally**.

## Stack

| Layer | Choice |
|---|---|
| App shell | Swift + SwiftUI `MenuBarExtra`, `LSUIElement` (no Dock icon) |
| Audio capture | Core Audio process taps (`CATapDescription` / aggregate device) for system audio + optional `AVAudioEngine` mic |
| ASR | Apple `SpeechAnalyzer` + `SpeechTranscriber` (`zh-CN`), volatile results for live partials |
| Translation | Apple `Translation` framework, `TranslationSession(installedSource:target:)` zh→en, high-fidelity strategy on 26.4+ |
| Overlay | Non-activating floating `NSPanel`, all Spaces, click-through, vibrancy |
| Trigger | Menu bar click or global hotkey (default ⌥⌘T) |

## Fallbacks (behind protocols)

- **ASR:** sherpa-onnx streaming Paraformer zh-en, or WhisperKit large-v3-turbo.
- **Translation:** local LLM via MLX (e.g. Qwen3 ~8B) with rolling context.

## UX

- Menu bar icon pulses while listening.
- Overlay sits at the bottom center: big English line, small Chinese above it, older lines fade out. The live line is dim and turns solid when final.
- Drag to move; the overlay remembers its position.
- Menu: source (system / mic / both), show or hide the Chinese, session history (copyable).

## Build & run

Only Command Line Tools are needed (no Xcode). Target: macOS 26.4+, Apple silicon.

```sh
scripts/make-signing-identity.sh   # once: self-signed identity in its own keychain
scripts/bundle.sh --run            # build/tingjian.app, (re)launch it
```

`bundle.sh` signs with the local identity so the designated requirement
(`identifier "com.pedroslopez.tingjian" and certificate leaf = …`) is stable and
privacy grants survive rebuilds. Without the identity it falls back to ad hoc
signing, which resets grants on every build.

- **Toggle:** menu bar icon › Start listening, or **⌥⌘T** anywhere.
- **Move the overlay:** hold **⌘**, then drag the subtitles. *Reset overlay position* is in the menu.
- **Scripting:** `open build/tingjian.app --args --start` starts listening on launch. Posting the
  distributed notification `com.pedroslopez.tingjian.toggle` toggles it.
- **Logs:** `log stream --predicate 'subsystem == "com.pedroslopez.tingjian"' --info`

### Permissions

| What | When | Where |
|---|---|---|
| System Audio Recording | first start with source *System* / *Both* | System Settings › Privacy & Security › Screen & System Audio Recording (*System Audio Recording Only*) |
| Microphone | first start with source *Mic* / *Both* | Privacy & Security › Microphone |

No Accessibility or Screen Recording permission is needed; the hotkey uses Carbon
`RegisterEventHotKey`. If the overlay only says "Only silence so far" while audio is
playing, the System Audio Recording grant is missing.

Models (on-device, one-time): the zh-CN speech model downloads automatically on first
start. The zh-Hans → en translation model must be installed under System Settings ›
General › Language & Region › Translation Languages.

### CLI

`swift run tingjian-cli <command>` runs the same pipeline headless:

- `check`: whether the zh-CN transcriber and the zh-Hans → en translation are installed.
- `install`: downloads the zh-CN speech model.
- `file <audio>`: plays a file through ASR and translation in real time.
- `tap [s]` / `mic [s]`: live capture.

Quick test: `say -v Tingting -o /tmp/zh.aiff "今天天气很好。" && swift run tingjian-cli file /tmp/zh.aiff`

## Layout

- `Sources/TingjianCore`: audio sources (process tap, mic, file), `SpeechRecognizer` / `Translator`
  protocols plus the Apple implementations, sentence segmentation, `Transcript`, and `ListeningSession`.
- `Sources/Tingjian`: the menu bar app (model, overlay panel, menu, hotkey).
- `Sources/tingjian-cli`: the feasibility check and headless runs.
