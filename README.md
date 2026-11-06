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

## Build

SwiftPM + `scripts/bundle.sh` → `.app` with Info.plist + ad-hoc codesign. Only Command Line Tools are needed (no Xcode).

Target: macOS 26+, Apple silicon.
