# Changelog

## 2026-08-14 [Claude] Cloud engine (Groq/OpenAI), Whisper perf, UI overhaul

- **Files:** `DictadoSwift/CloudEngine.swift` + `tests/test_cloudengine.swift` (new); `SpeechManager.swift`, `SettingsManager.swift`, `ContentView.swift`, `ModelManager.swift`, `DictadoWhisperApp.swift`, `build.sh`, `tests/run_tests.sh`.
- **Change:** Third engine "Nube" — OpenAI-compatible transcription client, Groq `whisper-large-v3-turbo` (default) or OpenAI `gpt-4o-mini-transcribe`, per-provider API key with locked Editar/Guardar UI. Whisper perf: engine preload (app start / settings change / recording start) + tiny/base/small **q5_1** quantized models in the catalog. UI: last transcription always visible with Copiar button; popover 450→770 px; settings card fills height (was capped at 230 px).
- **Reason:** Operator's Intel i9 was slow with the `small` model; investigation showed Wispr Flow is cloud-only, so a cloud option was added — Groq measured live at 1.5 s round-trip for an 11 s clip with large-v3 accuracy. Local wins (preload, q5_1) keep the offline path usable.
- **Deploy:** local app rebuilt + installed on the Intel Mac; `main` = `75b37f2` (+ this docs commit). Suite 4/4 green. Office Mac install pending (operator).

## 2026-06-14 [Claude] Native whisper.cpp engine; remove Python

- **Files (new):** `DictadoSwift/WhisperEngine.swift`, `AudioRecorder.swift`, `ModelManager.swift`, `whisper-bridging.h`, `scripts/build_whisper_lib.sh`, `tests/{test_engine,test_audio,test_modelmanager}.swift`, `tests/run_tests.sh`, `.gitignore`, `PROJECT_STATUS.md`, `CHANGELOG.md`, `docs/superpowers/specs/2026-06-14-whisper-native-engine-design.md`, `docs/superpowers/plans/2026-06-14-whisper-native-engine.md`.
- **Files (modified):** `SpeechManager.swift`, `SettingsManager.swift`, `ContentView.swift`, `build.sh`, `CLAUDE.md`, `install.md`.
- **Files (removed):** `dictado_whisper.py`, `build_app.py`, `setup.sh`, `config.json`, `__pycache__/`. Moved `Guia_Resolucion_Problemas.md` → `docs/legacy/`.
- **Change:** Replaced the broken Python-subprocess "Whisper" engine with whisper.cpp (pinned v1.8.6) compiled natively into the Swift app and called via a bridging header. Audio captured as 16 kHz mono float32 by `AudioRecorder`; models downloaded with a real progress bar by `ModelManager`; transcription via `WhisperEngine` with auto language detection. Apple `SFSpeechRecognizer` engine retained as the secondary option. `build.sh` now compiles+links whisper.cpp and pins vendor libs to the macOS 13 deployment target.
- **Reason:** The subprocess didn't inherit the app's mic/Accessibility permissions and registered a colliding global hotkey ("opens the old window, errors, does nothing"); no download progress; user wanted real Whisper with multi-language auto-detection.
- **Bug fixes folded in:** Apple isFinal (was blind 1s timer, truncated long dictations), on-device support guard, ModelManager `tasks` data race (main-queue delegate), Whisper transcription serial queue (engine/model race), `build.sh` killall using the wrong executable name, engine-latch so stop routes correctly after a mid-recording engine switch, and the `detect_language=true` regression (auto-detected the language but returned zero segments → "no se detectó voz").
- **Repo hygiene:** untracked `DictadoSwift/build/` (build artifacts were committed before `.gitignore` existed).
- **Deploy:** local macOS app, no server. Pushed to `main` (https://github.com/sirlukkes/whisper). Verified building natively on Intel (x86_64) and Apple Silicon (arm64).
