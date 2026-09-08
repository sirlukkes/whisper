# PROJECT_STATUS — Conetxo Listener (ex Dictado Whisper)

> Last update: 2026-09-08 — Launch-at-login shipped (SMAppService toggle in settings + menu, quiet startup when launched by login). App rebuilt and installed on the Intel Mac. `main` = see `git log -1`.

## TODO — dictados por el operador

- [ ] 2026-08-14 — Install on the office Mac: `git pull && cd DictadoSwift && ./build.sh` (works on Intel or Apple Silicon; needs `cmake`). Paste the Groq API key there and grant Microphone + Accessibility.
- [ ] 2026-08-14 — One unexplained error during a cloud dictation (exact status message not captured; possibly the app being replaced mid-dictation by a rebuild). If it repeats, capture the status text — "Sin conexión con el servicio" / "Error del servicio (HTTP nnn)" / "API key inválida" each point to a different cause.
- [ ] 2026-08-14 — Operator reports the auto-paste sometimes doesn't land ("a veces no me copian"). Mitigated by the always-visible last transcription + Copiar button; root cause not investigated yet.

## Estado actual

- Working. Three engines (whisper.cpp local default, Apple, cloud Groq/OpenAI). Architecture, topology and the "why" behind decisions: `CLAUDE.md`. History: `CHANGELOG.md`.
- 2026-09-08: "Iniciar al encender el Mac" toggle (settings card + right-click menu) via `SMAppService.mainApp`; state read from the system, never from UserDefaults. When launched as a login item the popover stays closed (only the menu-bar icon shows).
- 2026-08-14 PM: rebranded to **Conetxo Listener** (bundle `com.conetxo.listener`, executable `ConetxoListener`, `BrandKit.swift`, About window, AppIcon + BrandLogo in `Resources/`).
- Popover is now 380×820 (was 770) to fit the new toggle without scrolling.
- Suite 4/4 green (engine, audio, modelmanager, cloudengine — all offline).

## Próximos pasos (none committed; confirm with Lukkes)

- Operator: enable the toggle once, then verify on the next login that the app appears in the menu bar WITHOUT opening the popover (the login-item detection via Apple Event is `[sin verificar]` on a real login).
- If local speed still matters: VAD-segmented streaming while recording, or prototype Moonshine-es / Parakeet-TDT (sherpa-onnx) — both avoid Whisper's 30 s window tax on CPU.
- Optional: Metal/GPU on Apple Silicon (`-DGGML_METAL=OFF` today), persistent `AVAudioConverter`.

## Pendientes / open items del operador

- See TODO section. Plus: after every rebuild the app is re-signed ad-hoc; if the login-item toggle ever shows OFF after a rebuild, just turn it on again.

## Known issues / deferred debt

- Paste flakiness (see TODO) — not root-caused.
- Chunk-by-chunk resampling in `AudioRecorder` (new `AVAudioConverter` per buffer) + no `error` check after `convert` — deferred.
- Metal/GPU not enabled — fine on Intel; suboptimal on Apple Silicon.
- Batch-at-stop design (no streaming while recording); cloud makes it fast enough in practice.

