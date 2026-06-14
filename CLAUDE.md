# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Dictado Whisper** — a macOS voice-dictation utility (Spanish-first). Press a global hotkey, speak, and the transcribed text is pasted at the cursor via simulated `Cmd+V`. 100% on-device / offline.

The repo contains a single native Swift implementation in `DictadoSwift/`. The old Python implementation has been removed; legacy troubleshooting notes are archived under `docs/legacy/`.

## Build & run

```bash
cd DictadoSwift && ./build.sh
```

`build.sh` compiles all `.swift` files with `swiftc` (no Xcode project), ad-hoc codesigns the bundle, installs to `/Applications`, and launches the app. On the first run it also clones and compiles whisper.cpp via cmake (takes ~1–2 min; needs `cmake` installed). Subsequent builds are fast.

Tests: `DictadoSwift/tests/run_tests.sh`

## Architecture

### Dual-engine design

`SettingsManager.engine` selects the transcription backend (default `"whisper"`):

- `"whisper"` — **WhisperEngine.swift** calls whisper.cpp via the C API declared in `whisper-bridging.h`. whisper.cpp is vendored under `DictadoSwift/vendor/` and compiled to a static lib by `DictadoSwift/scripts/build_whisper_lib.sh`. Audio is captured by **AudioRecorder.swift** as 16 kHz mono float32 PCM. Models are downloaded with a progress bar by **ModelManager.swift**; they live in `~/Library/Application Support/DictadoWhisper/models/`. Default model: `base` (~142 MB). Language defaults to `es-ES`; can be set to `auto` for multilingual auto-detection.
- `"apple"` — `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. Audio captured via `AVAudioEngine` tap; partial results stream into `currentTranscription`.

### Component map

- **DictadoWhisperApp.swift** — `AppDelegate`, menu-bar `NSStatusItem`, transient `NSPopover` hosting the SwiftUI view.
- **HotkeyManager.swift** — global hotkey via Carbon `RegisterEventHotKey` (keycode + modifier bitmask), posts `.globalHotkeyTriggered`.
- **SettingsManager.swift** — `UserDefaults`-backed settings + keycode↔name mapping. Migrates legacy `"whisper_python"` engine value to `"whisper"` on first run.
- **SpeechManager.swift** — orchestrates recording and engine dispatch.
- **HistoryManager.swift** — last 50 transcriptions in `UserDefaults`, also appended to `~/Documents/DictadoWhisper_Historial.md`.
- **ContentView.swift** — SwiftUI settings/history UI.
- Components communicate via `NotificationCenter` (`.globalHotkeyTriggered`, `.recordingStateChanged`, `.whisperSettingsChanged`, `.hotkeyChanged`, `.themeChanged`).

### Paste flow

Transcribe → copy to clipboard → restore focus to the previously-active app → simulate `Cmd+V`. The app tracks `lastActiveApp`/`previousApp` via `NSWorkspace` notifications so dictation lands in the right window, and uses `CGEvent` for paste when Accessibility is granted, falling back to AppleScript otherwise.

## Critical macOS constraints

- **Accessibility permission** required for paste (`CGEvent`). Declare in `Info.plist`; grant in System Settings → Privacy & Security → Accessibility.
- **Gatekeeper quarantine:** the app is ad-hoc signed, so Gatekeeper may block it. Clear with `xattr -rc "/Applications/Dictado Whisper.app"`.
- **Permissions declared in Info.plist:** Microphone and Accessibility — macOS fails silently if keys are missing.

## Conventions

This is existing Spanish-language code (comments, identifiers, UI strings, log messages). Per the global English-code rule, anglify organically when touching a file — don't open a translation-only pass. UI-facing strings stay Spanish (this is a Spanish-first product).

Spec and plan live in `docs/superpowers/`.
