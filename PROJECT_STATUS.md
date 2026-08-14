# PROJECT_STATUS — Dictado Whisper

> Last update: 2026-08-14 — Cloud engine (Groq/OpenAI) shipped + Whisper perf (engine preload, q5_1 quantized models) + UI overhaul (770px popover, always-visible last transcription, locked API key). App rebuilt and installed on the Intel Mac.

## TODO — dictados por el operador

- [ ] 2026-08-14 — Install on the office Mac: `git pull && cd DictadoSwift && ./build.sh` (works on Intel or Apple Silicon; needs `cmake`). Paste the Groq API key there and grant Microphone + Accessibility.
- [ ] 2026-08-14 — One unexplained error during a cloud dictation (exact status message not captured; possibly the app being replaced mid-dictation by a rebuild). If it repeats, capture the status text — "Sin conexión con el servicio" / "Error del servicio (HTTP nnn)" / "API key inválida" each point to a different cause.
- [ ] 2026-08-14 — Operator reports the auto-paste sometimes doesn't land ("a veces no me copian"). Mitigated by the always-visible last transcription + Copiar button; root cause not investigated yet.

## 1. Goal

macOS menu-bar voice-dictation app (Spanish-first). Press a global hotkey, speak, the transcribed text is pasted at the cursor via simulated `Cmd+V`. Local engines are 100% on-device; an optional cloud engine (Groq/OpenAI) trades offline for speed+accuracy.

## 2. File structure (current)

Single native Swift app in `DictadoSwift/` (built with `swiftc`, no Xcode project, no SwiftPM):

- `DictadoWhisperApp.swift` — AppDelegate, menu-bar `NSStatusItem` (mic SF Symbol), transient popover (380×770).
- `SpeechManager.swift` — orchestrator; routes between the three engines, latches the active engine at start, preloads the Whisper model.
- `WhisperEngine.swift` — wraps whisper.cpp (load model, transcribe `[Float]` → text).
- `CloudEngine.swift` — OpenAI-compatible `/audio/transcriptions` client (WAV PCM16 multipart); providers: Groq `whisper-large-v3-turbo` (default) and OpenAI `gpt-4o-mini-transcribe`.
- `AudioRecorder.swift` — AVAudioEngine + AVAudioConverter → 16 kHz mono float32.
- `ModelManager.swift` — model catalog (incl. tiny/base/small **q5_1** quantized) + download-with-progress + integrity check.
- `SettingsManager.swift`, `HotkeyManager.swift`, `HistoryManager.swift`, `ContentView.swift` — settings (incl. cloud provider + per-provider API key), Carbon hotkey, history, SwiftUI.
- `whisper-bridging.h` — exposes whisper.h to Swift.
- `scripts/build_whisper_lib.sh` — clones (pinned v1.8.6) + cmake-builds whisper.cpp static libs.
- `build.sh` — builds lib, compiles+links the app (source list is EXPLICIT — new .swift files must be added there), ad-hoc codesigns, installs to `/Applications`, launches.
- `tests/` — `test_engine`, `test_audio`, `test_modelmanager`, `test_cloudengine` (WAV/multipart/auth, offline); `run_tests.sh` runs all four.
- `vendor/whisper.cpp/` — git-ignored pinned clone (created by the build script).
- `docs/superpowers/` — design spec + implementation plan. `docs/legacy/` — archived Python-era troubleshooting doc.

Architecture details: see `CLAUDE.md`.

## 3. Functional state

✅ Done (2026-06-14 base + this session):

- Native Whisper engine (whisper.cpp v1.8.6), multilingual auto-detect, model download progress, Apple engine kept.
- **Cloud engine**: Groq verified live with the operator's key (11s clip → 1.5s round-trip, HTTP 200). Errors surface as short Spanish status messages, never silent.
- **Whisper perf**: engine preloaded at app start / settings change / recording start (first dictation no longer pays model load); q5_1 models measured on the i9-10910 (11s clip, load + 2 passes): small 8.7s → small-q5_1 6.5s; base 2.5s → base-q5_1 2.1s.
- **UI**: last transcription always on the main screen (seeded from history) with Copiar button + selectable text; API key locked once saved (Editar → draft → Guardar/Cancelar); popover 770px, no internal scrolling for settings.
- 4 automated tests green.

⏳ Pending / user-side: see TODO section above.

## 4. Next steps (none committed; confirm with Lukkes)

- If local speed still matters: VAD-segmented incremental transcription while recording (whisper.cpp `stream` pattern + Silero VAD), and/or prototype Moonshine-es or Parakeet-TDT via sherpa-onnx (both avoid Whisper's 30s-window tax on CPU; research 2026-08-14 in session notes).
- Optional: Metal/GPU on Apple Silicon (`-DGGML_METAL=OFF` today), AppIcon.icns, persistent `AVAudioConverter`.

## 5. Topology / hosting / URLs

- Repo: https://github.com/sirlukkes/whisper (branch `main`, direct-to-main, no PRs).
- No server. Local macOS app. Cloud engine calls `api.groq.com` / `api.openai.com` directly.
- Models download from Hugging Face (`ggerganov/whisper.cpp`) to `~/Library/Application Support/DictadoWhisper/models/`.
- App installs to `/Applications/Dictado Whisper.app` (ad-hoc signed → needs `xattr -rc` if transferred between Macs).
- API keys: `console.groq.com/keys` / `platform.openai.com/api-keys`; stored per-machine in UserDefaults.

## 6. Technical decisions (esp. changes from the original plan)

- **whisper.cpp over WhisperKit** — Intel CPU support. Pinned v1.8.6 (commit `23ee0350`).
- **Cloud = Groq by default** — same Whisper family (large-v3-turbo: ~4% Spanish WER vs ~10% of local `small`), ~9x cheaper than OpenAI ($0.08 vs $0.72 per 120 min/mo), fastest measured. One `CloudEngine` covers both providers (OpenAI-compatible endpoint).
- **Language stays `"auto"` for Whisper AND cloud** — operator dictates in English sometimes (explicitly declined hardcoding "es").
- **Quantized q5_1 only** (not q5_0/q8_0) — on x86 those are *slower* than q5_1 due to unpack overhead.
- **API keys in UserDefaults** (plaintext plist) — deliberate for a personal app; ad-hoc re-signing on every rebuild would make Keychain prompt constantly. Move to Keychain if ever distributed.
- **`detect_language` must stay false** — `language="auto"` alone auto-detects AND transcribes; `true` returns zero segments (the "no se detectó voz" bug).
- **Vendored + cmake build** (not SwiftPM/Xcode); static libs → self-contained `.app`; libs pinned to macOS 13 target.

## 7. Known issues / deferred debt

- Paste flakiness reported by the operator (see TODO) — not yet root-caused.
- Chunk-by-chunk resampling in `AudioRecorder` (new `AVAudioConverter` per buffer; sub-perceptible) + no `error` check after `convert` — deferred.
- Metal/GPU not enabled — fine on Intel; suboptimal on Apple Silicon.
- Wispr Flow-style instant feel would need streaming-while-recording; current design is batch-at-stop (cloud makes it fast enough in practice).

## 8. Historical context

The repo originally had TWO implementations: a Python/Tkinter script and a Swift app that launched it as a subprocess (permissions + hotkey collisions → broken). 2026-06-14 replaced that with native whisper.cpp and deleted all Python (notes in `docs/legacy/`). 2026-08-14 investigated "why is Wispr Flow so fast" → it's cloud-only (their docs: "Transcription always occurs on the cloud"), which motivated the optional cloud engine.
