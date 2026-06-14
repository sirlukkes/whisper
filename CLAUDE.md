# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Dictado Whisper** — a macOS voice-dictation utility (Spanish-first). Press a global hotkey, speak, and the transcribed text is pasted at the cursor via simulated `Cmd+V`. 100% on-device / offline.

The repo contains **two parallel implementations of the same product**, plus a bridge between them:

1. **Python** ([dictado_whisper.py](dictado_whisper.py)) — Tkinter GUI app using OpenAI Whisper (local model). Records via `sounddevice`, transcribes with the Whisper model, pastes via `pyautogui`.
2. **Swift** ([DictadoSwift/](DictadoSwift/)) — Native menu-bar app (`LSUIElement`, no Dock icon). Default engine is Apple's on-device `SFSpeechRecognizer`; it can also spawn the Python script as an alternate engine.

These are not independent forks — the Swift app can drive the Python script as a subprocess, and they share one config file.

## Build & run

### Python implementation
```bash
./setup.sh                       # installs Homebrew, Python 3.12, ffmpeg, portaudio + pip deps; removes app quarantine
python3.12 dictado_whisper.py    # run with GUI
python3.12 dictado_whisper.py --headless   # run hidden (how the Swift app launches it)
python build_app.py              # package into "Dictado Whisper.app" (lightweight wrapper, NOT PyInstaller)
```
Python deps (no requirements.txt): `openai-whisper torch sounddevice soundfile numpy pyautogui pynput`.

### Swift implementation
```bash
cd DictadoSwift && ./build.sh    # swiftc compile → ad-hoc codesign → install to /Applications → launch
```
`build.sh` rebuilds from scratch every time (`rm -rf build`), kills any running instance, and reuses the existing `AppIcon.icns` from `/Applications` if present. There is no Xcode project — compilation is a direct `swiftc` call over all `.swift` files targeting `arm64`/`x86_64` macOS 13.0.

No test suite exists for either implementation.

## Architecture

### The config bridge (integration point between the two apps)
`~/.dictado_whisper_config.json` is the shared source of truth.
- The Python app reads/writes it directly (`CONFIG_FILE` in [dictado_whisper.py](dictado_whisper.py)).
- The Swift `SettingsManager.saveToPythonConfig()` writes the same file whenever a relevant setting changes, translating Swift settings → Python keys (e.g. Swift locale `es-ES` → Python `language: "es"`; `whisperModel` → `model_size`).

When changing config schema, update **both** sides or the bridge silently drops fields.

### Swift dual-engine design ([SpeechManager.swift](DictadoSwift/SpeechManager.swift))
The `engine` setting selects the transcription backend:
- `"apple"` — `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. Audio captured via `AVAudioEngine` tap; partial results stream into `currentTranscription`.
- `"whisper_python"` — launches `dictado_whisper.py --headless` as a `Process`, parses `[LOG] ` lines from its stdout to surface status/download progress in the Swift UI, and tears the process down on engine switch (to free GPU/RAM) or settings change.

> **Gotcha:** the Python script path is **hardcoded** to `/Users/lukkes/Developer/whisper/dictado_whisper.py` in `SpeechManager.launchPythonApp()`. Moving the repo breaks the `whisper_python` engine.

### Paste flow (both apps)
Transcribe → copy to clipboard → restore focus to the previously-active app → simulate `Cmd+V`. The Swift app tracks `lastActiveApp`/`previousApp` via `NSWorkspace` notifications so dictation lands in the right window, and uses `CGEvent` for paste when Accessibility is granted, falling back to AppleScript otherwise.

### Swift component map
- [DictadoWhisperApp.swift](DictadoSwift/DictadoWhisperApp.swift) — `AppDelegate`, menu-bar `NSStatusItem`, transient `NSPopover` hosting the SwiftUI view.
- [HotkeyManager.swift](DictadoSwift/HotkeyManager.swift) — global hotkey via Carbon `RegisterEventHotKey` (keycode + modifier bitmask), posts `.globalHotkeyTriggered`.
- [SettingsManager.swift](DictadoSwift/SettingsManager.swift) — `UserDefaults`-backed settings + the Python config bridge + keycode↔name mapping.
- [HistoryManager.swift](DictadoSwift/HistoryManager.swift) — last 50 transcriptions in `UserDefaults`, also appended to `~/Documents/DictadoWhisper_Historial.md`.
- [ContentView.swift](DictadoSwift/ContentView.swift) — SwiftUI settings/history UI.
- Components communicate via `NotificationCenter` (`.globalHotkeyTriggered`, `.recordingStateChanged`, `.whisperSettingsChanged`, `.hotkeyChanged`, `.themeChanged`).

## Critical macOS constraints (cost real debugging — see [Guia_Resolucion_Problemas.md](Guia_Resolucion_Problemas.md))

- **Threading (Python):** Accessibility/keyboard APIs (`pyautogui`) MUST run on the main thread or the app crashes with `SIGILL`. Always marshal via `root.after(0, ...)`.
- **pynput listener (Python):** create the `keyboard.Listener` **once**; never stop+recreate (causes `SIGILL`). To change the hotkey, rewrite the global `shortcut` variable the live listener reads — don't restart the thread.
- **`$PATH` in .app bundles:** GUI apps get a stripped `$PATH` without `/usr/local/bin` or `/opt/homebrew/bin`, so `ffmpeg` isn't found. The Python script injects these paths at startup; the Swift subprocess launcher injects them into the child env.
- **Device selection (Python):** `get_device()` only enables MPS on Apple Silicon — Intel Macs report MPS available but crash loading the model, so they're forced to CPU. `fp16=True` only when device ≠ cpu.
- **Permissions required:** Microphone, Accessibility (for paste), and (Swift) Speech Recognition — all declared in `Info.plist`. Without the plist keys macOS fails silently.
- **Distribution:** apps are ad-hoc signed, so Gatekeeper quarantines them. Clear with `xattr -rc "/Applications/Dictado Whisper.app"`.

## Conventions

This is existing Spanish-language code (comments, identifiers, UI strings, log messages). Per the global English-code rule, anglify organically when touching a file — don't open a translation-only pass. UI-facing strings stay Spanish (this is a Spanish-first product).
