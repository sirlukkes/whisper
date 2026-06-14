# Native Whisper Engine — Design Spec

**Date:** 2026-06-14
**Status:** Approved (design), pending implementation plan
**Target machine:** macOS 26.x, Intel Core i9 (x86_64), no Apple Silicon / no Metal

## Problem

The app **Dictado Whisper** currently offers two transcription engines selected by a setting:

- `apple` — `SFSpeechRecognizer`, fully native, works correctly.
- `whisper_python` — launches the legacy `dictado_whisper.py` script as a **separate background process**.

The Python engine is broken by design: the spawned subprocess does **not** inherit the Swift app's microphone/Accessibility (TCC) permissions, so it cannot record or paste ("opens the old window, errors, does nothing"). It also registers its **own** global hotkey via `pynput`, colliding with the Swift Carbon hotkey, and download progress only surfaces if the subprocess survives long enough to emit `[LOG]` lines — which it doesn't. The whole subprocess design is the root cause.

## Goals

1. Run **real Whisper natively inside the Swift process** — no Python, no subprocesses, no second app.
2. **Multi-language with auto-detection**: the user speaks in any language and it is recognized without changing a language selector.
3. **Visible, real download progress** for models, so the app never looks frozen while a model downloads.
4. Keep the existing, working `apple` engine as a fast secondary option.
5. Remove all Python from the repo.

## Non-Goals

- Apple Silicon / Metal / CoreML optimization (machine is Intel; CPU + Accelerate is the target).
- Streaming/partial Whisper results (Whisper transcribes the full buffer after recording stops; Apple keeps its live partials).
- Translation mode (transcribe in the spoken language only).

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Whisper backend | **whisper.cpp** (ggerganov) | Runs on Intel CPU with Accelerate; multi-language auto-detect; ggml `.bin` models; no Python. WhisperKit rejected — it targets Apple Silicon/CoreML and is poor on Intel. |
| Integration | **Vendored + compiled by `build.sh` with cmake** | Keeps the "one script" build flow. whisper.cpp cloned into `DictadoSwift/vendor/`, pinned to a stable tag/commit, compiled to a static library, linked via a bridging header. |
| Engines | **Keep both** `apple` + `whisper`, **default `whisper`** | Apple already works and gives an instant, monolingual option; Whisper is the precise multi-language default. |
| Default model | **`base` (~142 MB)** | Best speed/quality balance on this CPU. Selector exposes `tiny`→`large`. |
| Model storage | `~/Library/Application Support/DictadoWhisper/models/` | Standard app data location; survives app rebuilds. |

## Architecture

Everything runs in the single Swift `.app` process, so microphone and Accessibility permissions (already granted to the app) apply to all transcription.

### New components

- **`WhisperEngine.swift`** — thin wrapper over whisper.cpp.
  - `init?(modelPath:)` → `whisper_init_from_file_with_params` (load once, reuse).
  - `transcribe(samples: [Float], language: String?) -> String?` → `whisper_full` with `language = "auto"` when `language` is nil/`"auto"`, `translate = false`, `n_threads = processorCount`, progress callbacks off; concatenates `whisper_full_get_segment_text` over `whisper_full_n_segments`.
  - `deinit` → `whisper_free`.
  - Dependency: whisper.cpp static lib via bridging header. Input contract: 16 kHz mono float32 PCM.

- **`ModelManager.swift`** — model catalog + download with progress (`ObservableObject`).
  - Catalog entries: `id` (tiny/base/small/medium/large-v3), display name, expected byte size, Hugging Face URL (`https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-<id>.bin`).
  - `@Published state` per model: `.notDownloaded | .downloading(fraction: Double, mb: String) | .ready | .failed(String)`.
  - Download via `URLSession` download task + delegate `didWriteData(totalBytesWritten:totalBytesExpectedToWrite:)` → publishes fraction + "x/y MB".
  - **Download is triggered when the user selects a model** (not lazily at first dictation), so progress is visible immediately.
  - Integrity: on completion verify file size ≈ expected; a partial/short file is deleted and re-downloaded. Never hand a truncated file to whisper.cpp.
  - `modelPath(for:)` → local path or nil if not ready.

- **`AudioRecorder.swift`** — capture + format conversion.
  - `AVAudioEngine` input tap → `AVAudioConverter` to 16 kHz, 1 channel, Float32 → accumulates `[Float]`.
  - `start()` / `stop() -> [Float]`. Used only by the Whisper engine (Apple engine keeps its own `SFSpeechAudioBufferRecognitionRequest`).

- **`whisper-bridging.h`** — `#include "whisper.h"` to expose the C API to Swift.

### Modified components

- **`SpeechManager.swift`** — orchestrator. **Remove all Python code** (`launchPythonApp`, `terminatePythonProcess`, `restartPythonProcess`, `getPythonPath`, `pythonProcess`, the settings-changed handler that restarts Python). Route by engine:
  - `apple` → existing `SFSpeechRecognizer` flow, with two bug fixes (below).
  - `whisper` → `AudioRecorder` records; on stop, ensure model is `.ready` (else show download), then `WhisperEngine.transcribe`; then the existing copy → restore focus → `Cmd+V` paste path; then save to history.
  - Unified `statusText` / `isRecording` for the UI in both engines (fixes the menu-bar icon never updating in the old Python mode).

- **`SettingsManager.swift`** — remove `saveToPythonConfig()` and all its call sites. `engine ∈ {apple, whisper}`, default `whisper`. `whisperModel` default `base`. Whisper language default `"auto"`.

- **`ContentView.swift`** — engine picker (Apple Local / Whisper Local). When Whisper: model picker (tiny→large) with per-model state and a **`ProgressView` showing download % + MB**. Language: add "Automático (detectar)" for Whisper; keep the locale list for Apple.

- **`build.sh`** — clone/update vendored whisper.cpp (pinned), `cmake` configure+build static lib (`-DBUILD_SHARED_LIBS=OFF -DGGML_METAL=OFF -DGGML_ACCELERATE=ON -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF`, `CMAKE_BUILD_TYPE=Release`), then `swiftc` with `-import-objc-header whisper-bridging.h`, the whisper/ggml include paths, the static lib search paths, `-lwhisper -lggml…`, `-framework Accelerate -lc++`. Library names/paths are confirmed against the pinned version during implementation. Keep the existing ad-hoc codesign + install-to-/Applications steps.

- **`Info.plist`** — no change required (microphone key already present; speech-recognition key stays for the Apple engine).

### Bug fixes folded in (from the code review)

- **Apple `stopRecording` blind 1.0 s timer** ([SpeechManager.swift:388]) → wait for the recognizer's `isFinal` result (with a timeout fallback) before reading the transcription, so long dictations aren't truncated.
- **`requiresOnDeviceRecognition` without guard** ([SpeechManager.swift:187]) → check `supportsOnDeviceRecognition` for the chosen locale and surface a clear message if unsupported.

## Data flow (Whisper engine)

1. Hotkey / mic button → start.
2. `AudioRecorder` captures, converts to 16 kHz mono float32, accumulates.
3. Stop → full `[Float]` buffer.
4. If the selected model isn't `.ready` → `ModelManager` downloads it, UI shows progress bar + % + MB.
5. `WhisperEngine.transcribe(samples, language: "auto")` → text.
6. Copy to clipboard → restore previous app focus → `Cmd+V` (existing logic, unchanged).
7. Save to history (existing `HistoryManager`).

## Files removed (Python era)

`dictado_whisper.py`, `build_app.py`, `setup.sh`, `config.json`, `__pycache__/`. `install.md` is rewritten for the native app. `Guia_Resolucion_Problemas.md` is Python-era history — archived (kept under a note) or deleted per user choice at execution time.

## Testing

- **Engine test (automated):** whisper.cpp ships `samples/jfk.wav`. After build, load `base` and transcribe `jfk.wav`; assert the output contains expected words (e.g. "country"). Validates the whole C↔Swift integration without a microphone.
- **Build test:** `build.sh` runs clean from a fresh checkout (vendored clone + cmake + swiftc + link).
- **Manual:** dictate real speech in Spanish, English, and a third language **without** changing the selector; verify auto-detection and paste at cursor. Verify the model download progress bar advances.

## Risks / open details (resolved during implementation)

- **ggml library names vary by whisper.cpp version** (`libggml`, `libggml-base`, `libggml-cpu`, …). The exact `-l` flags and lib paths are confirmed against the pinned tag when wiring `build.sh`.
- **Codesign:** the static lib is linked into the single binary; the existing ad-hoc `codesign --deep` should keep working. Verified in the build test.
- **First build is slow** (~1–2 min compiling C/C++). Acceptable; subsequent builds reuse the cmake build dir.
- **Permissions:** because transcription is now in-process, the app's existing microphone grant covers Whisper — this is precisely what fixes the broken Python mode.
