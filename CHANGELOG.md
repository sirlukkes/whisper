# Changelog

## 2026-06-14 [Claude] Native whisper.cpp engine; remove Python

- **Files (new):** `DictadoSwift/WhisperEngine.swift`, `AudioRecorder.swift`, `ModelManager.swift`, `whisper-bridging.h`, `scripts/build_whisper_lib.sh`, `tests/{test_engine,test_audio,test_modelmanager}.swift`, `tests/run_tests.sh`, `.gitignore`, `PROJECT_STATUS.md`, `CHANGELOG.md`, `docs/superpowers/specs/2026-06-14-whisper-native-engine-design.md`, `docs/superpowers/plans/2026-06-14-whisper-native-engine.md`.
- **Files (modified):** `SpeechManager.swift`, `SettingsManager.swift`, `ContentView.swift`, `build.sh`, `CLAUDE.md`, `install.md`.
- **Files (removed):** `dictado_whisper.py`, `build_app.py`, `setup.sh`, `config.json`, `__pycache__/`. Moved `Guia_Resolucion_Problemas.md` → `docs/legacy/`.
- **Change:** Replaced the broken Python-subprocess "Whisper" engine with whisper.cpp (pinned v1.8.6) compiled natively into the Swift app and called via a bridging header. Audio captured as 16 kHz mono float32 by `AudioRecorder`; models downloaded with a real progress bar by `ModelManager`; transcription via `WhisperEngine` with auto language detection. Apple `SFSpeechRecognizer` engine retained as the secondary option. `build.sh` now compiles+links whisper.cpp and pins vendor libs to the macOS 13 deployment target.
- **Reason:** The subprocess didn't inherit the app's mic/Accessibility permissions and registered a colliding global hotkey ("opens the old window, errors, does nothing"); no download progress; user wanted real Whisper with multi-language auto-detection.
- **Bug fixes folded in:** Apple isFinal (was blind 1s timer, truncated long dictations), on-device support guard, ModelManager `tasks` data race (main-queue delegate), Whisper transcription serial queue (engine/model race), `build.sh` killall using the wrong executable name, engine-latch so stop routes correctly after a mid-recording engine switch, and the `detect_language=true` regression (auto-detected the language but returned zero segments → "no se detectó voz").
- **Repo hygiene:** untracked `DictadoSwift/build/` (build artifacts were committed before `.gitignore` existed).
- **Deploy:** local macOS app, no server. Pushed to `main` (https://github.com/sirlukkes/whisper). Verified building natively on Intel (x86_64) and Apple Silicon (arm64).
