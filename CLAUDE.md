# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Conetxo Listener** (formerly Dictado Whisper; bundle `com.conetxo.listener`, executable `ConetxoListener`, branding constants in `BrandKit.swift`) — a macOS voice-dictation utility (Spanish-first). Press a global hotkey, speak, and the transcribed text is pasted at the cursor via simulated `Cmd+V`. 100% on-device / offline.

The repo contains a single native Swift implementation in `DictadoSwift/`. The old Python implementation has been removed; legacy troubleshooting notes are archived under `docs/legacy/`.

## Build & run

```bash
cd DictadoSwift && ./build.sh
```

`build.sh` compiles all `.swift` files with `swiftc` (no Xcode project), ad-hoc codesigns the bundle, installs to `/Applications`, and launches the app. On the first run it also clones and compiles whisper.cpp via cmake (takes ~1–2 min; needs `cmake` installed). Subsequent builds are fast.

Tests: `DictadoSwift/tests/run_tests.sh`

## Architecture

### Triple-engine design

`SettingsManager.engine` selects the transcription backend (default `"whisper"`):

- `"whisper"` — **WhisperEngine.swift** calls whisper.cpp via the C API declared in `whisper-bridging.h`. whisper.cpp is vendored under `DictadoSwift/vendor/` and compiled to a static lib by `DictadoSwift/scripts/build_whisper_lib.sh`. Audio is captured by **AudioRecorder.swift** as 16 kHz mono float32 PCM. Models are downloaded with a progress bar by **ModelManager.swift** (catalog includes q5_1 quantized variants — faster on Intel; q5_0/q8_0 deliberately excluded, slower on x86); they live in `~/Library/Application Support/DictadoWhisper/models/`. The engine is preloaded at app start / settings change / recording start so dictation never pays model-load time. Whisper always transcribes with `language="auto"` (operator dictates Spanish AND English — do not hardcode "es").
- `"apple"` — `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. Audio captured via `AVAudioEngine` tap; partial results stream into `currentTranscription`.
- `"cloud"` — **CloudEngine.swift**, OpenAI-compatible `/audio/transcriptions` multipart client. Providers: Groq `whisper-large-v3-turbo` (default) and OpenAI `gpt-4o-mini-transcribe`; per-provider API key in `SettingsManager` (UserDefaults — deliberate: ad-hoc re-signing on each rebuild would make Keychain prompt constantly). Language omitted → provider auto-detects.

`build.sh` lists source files EXPLICITLY — a new `.swift` file must be added there or the build fails with "cannot find X in scope".

### Component map

- **DictadoWhisperApp.swift** — `AppDelegate`, menu-bar `NSStatusItem`, transient `NSPopover` hosting the SwiftUI view.
- **HotkeyManager.swift** — global hotkey via Carbon `RegisterEventHotKey` (keycode + modifier bitmask), posts `.globalHotkeyTriggered`.
- **SettingsManager.swift** — `UserDefaults`-backed settings + keycode↔name mapping. Migrates legacy `"whisper_python"` engine value to `"whisper"` on first run.
- **SpeechManager.swift** — orchestrates recording and engine dispatch.
- **LaunchAtLoginManager.swift** — `SMAppService.mainApp` wrapper (register/unregister + `launchedAsLoginItem()` via the `keyAELaunchedAsLogInItem` Apple Event). State is read from the system, never cached in UserDefaults. `build.sh` links `-framework ServiceManagement`.
- **HistoryManager.swift** — last 50 transcriptions in `UserDefaults`, also appended to `~/Documents/DictadoWhisper_Historial.md`.
- **ContentView.swift** — SwiftUI settings/history UI.
- Components communicate via `NotificationCenter` (`.globalHotkeyTriggered`, `.recordingStateChanged`, `.whisperSettingsChanged`, `.hotkeyChanged`, `.themeChanged`).

### Paste flow

Transcribe → copy to clipboard → restore focus to the previously-active app → simulate `Cmd+V`. The app tracks `lastActiveApp`/`previousApp` via `NSWorkspace` notifications so dictation lands in the right window, and uses `CGEvent` for paste when Accessibility is granted, falling back to AppleScript otherwise.

## Critical macOS constraints

- **Accessibility permission** required for paste (`CGEvent`). Declare in `Info.plist`; grant in System Settings → Privacy & Security → Accessibility.
- **Gatekeeper quarantine:** the app is ad-hoc signed, so Gatekeeper may block it. Clear with `xattr -rc "/Applications/Conetxo Listener.app"`.
- **Permissions declared in Info.plist:** Microphone and Accessibility — macOS fails silently if keys are missing.

## Topology

- Repo: `github.com/sirlukkes/whisper`, branch `main`, direct-to-main, no PRs. No server; local macOS app (macOS 13+).
- Installs to `/Applications/Conetxo Listener.app` (ad-hoc signed). Running check: `pgrep -fl ConetxoListener`. Menu-bar only (`LSUIElement`), no Dock icon.
- Cloud engine calls `api.groq.com` / `api.openai.com` directly; keys from `console.groq.com/keys` / `platform.openai.com/api-keys`, stored per-machine in UserDefaults.
- Models: Hugging Face `ggerganov/whisper.cpp` → `~/Library/Application Support/DictadoWhisper/models/`.

## Decisions worth knowing before changing things

- **whisper.cpp over WhisperKit** — Intel CPU support. Pinned v1.8.6 (`23ee0350`).
- **Cloud default = Groq** — same Whisper family (large-v3-turbo), ~9x cheaper than OpenAI, fastest measured (11 s clip → 1.5 s).
- **`detect_language` stays `false`** — `true` returns zero segments ("no se detectó voz"); `language="auto"` alone detects AND transcribes.
- **Launch-at-login state lives in the system** (`SMAppService.mainApp.status`), because the user can also toggle it in System Settings; a cached flag would lie. When launched by login the startup popover is suppressed.
- **Vendored + cmake build**, not SwiftPM/Xcode; static libs → self-contained `.app`.

## Conventions

This is existing Spanish-language code (comments, identifiers, UI strings, log messages). Per the global English-code rule, anglify organically when touching a file — don't open a translation-only pass. UI-facing strings stay Spanish (this is a Spanish-first product).

Spec and plan live in `docs/superpowers/`.
