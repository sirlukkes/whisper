# PROJECT_STATUS — Dictado Whisper

> Last update: 2026-06-14 — Native whisper.cpp engine shipped; app builds, runs, and transcribes on Intel and Apple Silicon. All Python removed.

## 1. Goal

macOS menu-bar voice-dictation app (Spanish-first). Press a global hotkey, speak, the transcribed text is pasted at the cursor via simulated `Cmd+V`. 100% on-device / offline after the model is downloaded.

## 2. File structure (current)

Single native Swift app in `DictadoSwift/` (built with `swiftc`, no Xcode project, no SwiftPM):

- `DictadoWhisperApp.swift` — AppDelegate, menu-bar `NSStatusItem` (mic SF Symbol), transient popover.
- `SpeechManager.swift` — orchestrator; routes between the two engines, latches the active engine at start.
- `WhisperEngine.swift` — wraps whisper.cpp (load model, transcribe `[Float]` → text).
- `AudioRecorder.swift` — AVAudioEngine + AVAudioConverter → 16 kHz mono float32.
- `ModelManager.swift` — model catalog + download-with-progress + integrity check.
- `SettingsManager.swift`, `HotkeyManager.swift`, `HistoryManager.swift`, `ContentView.swift` — settings, Carbon hotkey, history, SwiftUI.
- `whisper-bridging.h` — exposes whisper.h to Swift.
- `scripts/build_whisper_lib.sh` — clones (pinned v1.8.6) + cmake-builds whisper.cpp static libs.
- `build.sh` — builds lib, compiles+links the app, ad-hoc codesigns, installs to `/Applications`, launches.
- `tests/` — `test_engine` (real jfk.wav transcription, both "en" and "auto"), `test_audio` (resample), `test_modelmanager` (progress math); `run_tests.sh` runs all three.
- `vendor/whisper.cpp/` — git-ignored pinned clone (created by the build script).
- `docs/superpowers/` — design spec + implementation plan. `docs/legacy/` — archived Python-era troubleshooting doc.

Architecture details: see `CLAUDE.md`.

## 3. Functional state

✅ Done:
- Native Whisper engine (whisper.cpp v1.8.6) compiled into the app — no Python, no subprocess.
- Multi-language auto-detection (`language="auto"`) — speak any language, no selector change.
- Real model-download progress bar (ModelManager + ContentView `ProgressView`).
- Apple `SFSpeechRecognizer` engine kept as secondary option (default is Whisper).
- Bug fixes: Apple isFinal (was blind 1s timer), on-device guard, 2 data races, build.sh killall name, engine-latch on mid-recording switch, and the `detect_language` regression (auto detected language but never transcribed).
- Builds + runs on Intel (native x86_64) and Apple Silicon (native arm64; `build.sh` auto-detects chip).
- 3 automated tests green.

⏳ Pending / user-side:
- On each Mac: grant Microphone + Accessibility permissions; first dictation downloads the `base` model (~142 MB).
- Live mic-capture + paste validated by the user (the automated test uses a file, not the mic). Reported working.

## 4. Next steps (none committed; confirm with Lukkes)

- Optional: make `build_whisper_lib.sh` chip-aware to enable **Metal/GPU** on Apple Silicon (currently `-DGGML_METAL=OFF`, CPU-only — correct for Intel, leaves GPU unused on Apple Silicon). Offered to the user; not yet done.
- Optional: bundle an `AppIcon.icns` (build warns it's missing; app uses generic icon — purely cosmetic, does NOT affect the menu-bar icon, which is an SF Symbol).
- Optional: persistent `AVAudioConverter` in `AudioRecorder` if real-world transcription quality suffers (see deferred debt below).

## 5. Topology / hosting / URLs

- Repo: https://github.com/sirlukkes/whisper (branch `main`, direct-to-main, no PRs).
- No server. Local macOS app only.
- Models download from Hugging Face (`ggerganov/whisper.cpp`) to `~/Library/Application Support/DictadoWhisper/models/` on first use.
- App installs to `/Applications/Dictado Whisper.app` (ad-hoc signed → needs `xattr -rc` if transferred between Macs).

## 6. Technical decisions (esp. changes from the original plan)

- **whisper.cpp over WhisperKit** — WhisperKit targets Apple Silicon/CoreML; whisper.cpp runs well on Intel CPU + Accelerate. Pinned v1.8.6 (commit `23ee0350`).
- **Vendored + cmake build** (not SwiftPM/Xcode) — keeps the one-script `build.sh` flow. Static libs linked into the binary → the `.app` is self-contained (no runtime dependency on `vendor/`).
- **Dual engine kept** — Apple (fast, monolingual, needs language set) + Whisper (default, multilingual auto, more accurate, slower on CPU).
- **`detect_language` must stay false** — with `language="auto"`, whisper.cpp auto-detects AND transcribes; `detect_language=true` makes `whisper_full` return right after detecting (zero segments). This was the "no se detectó voz" bug.
- **Libs pinned to macOS 13 deployment target** (`-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0`) to silence linker warnings.

## 7. Known issues / deferred debt

- **Chunk-by-chunk resampling** in `AudioRecorder.resampleToWhisperFormat` creates a new `AVAudioConverter` per buffer (~0.1 ms boundary artifact every ~85 ms — sub-perceptible for Whisper's 25 ms mel windows). Deferred; fix = persistent converter in `start()` if real transcription quality ever suffers (>1 wrong word / 30 s with no other cause).
- **No `error` check after `AVAudioConverter.convert`** in AudioRecorder — silent-failure edge, non-blocking.
- **Metal/GPU not enabled** — CPU-only build. Fine on Intel; suboptimal on Apple Silicon.

## 8. Historical context

The repo originally had TWO implementations of the same product: a Python/Tkinter script (`dictado_whisper.py`, OpenAI Whisper) and a Swift app that, in "Whisper" mode, launched the Python script as a subprocess. That subprocess didn't inherit the app's mic/Accessibility permissions and registered a colliding global hotkey → "opens the old window, errors, does nothing". This session replaced the subprocess with native whisper.cpp and deleted all Python. The Python-era troubleshooting notes are archived in `docs/legacy/`.
