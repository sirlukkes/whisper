# Native Whisper Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken Python-subprocess "Whisper" engine with whisper.cpp compiled and linked natively into the Swift app, with multi-language auto-detection and a real model-download progress bar; keep the working Apple engine.

**Architecture:** whisper.cpp (pinned v1.8.6) is cloned into `DictadoSwift/vendor/` and compiled to static libraries by `build.sh` via cmake (CPU + Accelerate, no Metal — the machine is Intel). Swift talks to it through a bridging header. A `WhisperEngine` wraps the C API, `AudioRecorder` produces the 16 kHz mono float32 buffer whisper.cpp needs, and `ModelManager` downloads ggml models with progress. `SpeechManager` becomes a pure in-process orchestrator routing between the `apple` and `whisper` engines — no subprocess, so the app's microphone/Accessibility grants cover everything.

**Tech Stack:** Swift 6.x (compiled with `swiftc`, no Xcode project / no SwiftPM), whisper.cpp v1.8.6 (C/C++ static lib via cmake), AVFoundation (capture + resample), Speech.framework (Apple engine), URLSession (downloads).

**Pinned dependency:** whisper.cpp `v1.8.6` = commit `23ee03506a91ac3d3f0071b40e66a430eebdfa1d`.

---

## File Structure

**New files (in `DictadoSwift/`):**
- `vendor/whisper.cpp/` — pinned clone (git-ignored; created by build script).
- `scripts/build_whisper_lib.sh` — clone+checkout v1.8.6, cmake-build static libs. Idempotent. Used by `build.sh` and tests.
- `whisper-bridging.h` — `#include "whisper.h"` for Swift interop.
- `WhisperEngine.swift` — wraps whisper.cpp: load model, transcribe `[Float]` → text, auto-detect language.
- `AudioRecorder.swift` — AVAudioEngine + AVAudioConverter → 16 kHz mono float32 `[Float]`.
- `ModelManager.swift` — model catalog, download-with-progress, integrity check, paths.
- `tests/test_engine.swift` — smoke: transcribe bundled `jfk.wav` with `base`, assert text.
- `tests/test_audio.swift` — assert AVAudioConverter produces 16 kHz mono.
- `tests/test_modelmanager.swift` — assert progress math + catalog + integrity logic.
- `tests/run_tests.sh` — compile + run the test binaries, report pass/fail.

**Modified:**
- `SpeechManager.swift` — remove ALL Python; route `apple`/`whisper`; fix Apple bugs.
- `SettingsManager.swift` — remove `saveToPythonConfig`; `engine ∈ {apple, whisper}` default `whisper`; `whisperModel` default `base`.
- `ContentView.swift` — engine picker, model picker + download progress bar, "Automático" language.
- `build.sh` — build whisper lib, then compile+link the app with it.
- `.gitignore` (create) — ignore `vendor/`, `build/`, `__pycache__/`, `*.bin`.

**Deleted (repo root):** `dictado_whisper.py`, `build_app.py`, `setup.sh`, `config.json`, `__pycache__/`. `install.md` rewritten. `Guia_Resolucion_Problemas.md` archived under `docs/legacy/`.

**Conventions:** New Swift code in English (identifiers, comments). User-facing UI strings stay Spanish. Each task ends with a commit on `main`.

---

## Task 1: Build infrastructure — vendor + compile whisper.cpp

**Files:**
- Create: `DictadoSwift/scripts/build_whisper_lib.sh`
- Create: `.gitignore`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Build artifacts
DictadoSwift/build/
DictadoSwift/vendor/
DictadoSwift/tests/*.bin
**/__pycache__/
*.pyc
# Whisper models (downloaded at runtime)
*.bin
.DS_Store
```

- [ ] **Step 2: Write `DictadoSwift/scripts/build_whisper_lib.sh`**

```bash
#!/bin/bash
# Clone (pinned) and compile whisper.cpp to static libraries for Intel macOS (CPU + Accelerate).
# Idempotent: skips clone/checkout/build if already present.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/../vendor/whisper.cpp"
WHISPER_TAG="v1.8.6"
WHISPER_COMMIT="23ee03506a91ac3d3f0071b40e66a430eebdfa1d"

if [ ! -d "$VENDOR_DIR/.git" ]; then
  echo "📥 Cloning whisper.cpp $WHISPER_TAG ..."
  git clone https://github.com/ggerganov/whisper.cpp "$VENDOR_DIR"
fi

echo "📌 Pinning whisper.cpp to $WHISPER_TAG ($WHISPER_COMMIT)"
git -C "$VENDOR_DIR" fetch --tags --quiet
git -C "$VENDOR_DIR" checkout --quiet "$WHISPER_COMMIT"

BUILD_DIR="$VENDOR_DIR/build"
if [ ! -f "$BUILD_DIR/.built_ok" ]; then
  echo "⚙️  Configuring + building whisper.cpp static libs (this is slow the first time)..."
  cmake -B "$BUILD_DIR" -S "$VENDOR_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=OFF \
    -DGGML_ACCELERATE=ON \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF
  cmake --build "$BUILD_DIR" --config Release -j
  touch "$BUILD_DIR/.built_ok"
fi

echo "✅ whisper.cpp libs:"
find "$BUILD_DIR" -name "*.a" -print
```

- [ ] **Step 3: Make executable and run it**

Run:
```bash
chmod +x DictadoSwift/scripts/build_whisper_lib.sh
DictadoSwift/scripts/build_whisper_lib.sh
```
Expected: clones whisper.cpp, cmake builds, and prints a list of `.a` files (e.g. `libwhisper.a`, `libggml.a`, `libggml-base.a`, `libggml-cpu.a` — exact set depends on v1.8.6). Build takes ~1–2 min.

- [ ] **Step 4: Verify the static libs and headers exist**

Run:
```bash
echo "--- libs ---"; find DictadoSwift/vendor/whisper.cpp/build -name "*.a"
echo "--- whisper.h ---"; ls DictadoSwift/vendor/whisper.cpp/include/whisper.h
echo "--- sample ---"; ls DictadoSwift/vendor/whisper.cpp/samples/jfk.wav
```
Expected: at least one `libwhisper.a` plus ggml `.a` files; `whisper.h` present; `jfk.wav` present. If `whisper.h` is under a different path, note the real path — Task 2 needs it.

- [ ] **Step 5: Commit**

```bash
git add .gitignore DictadoSwift/scripts/build_whisper_lib.sh
git commit -m "build: add vendored whisper.cpp v1.8.6 static-lib build script"
```

---

## Task 2: WhisperEngine + native integration smoke test

This is the de-risking task: it proves Swift↔whisper.cpp compiles, links, and transcribes. Do it before anything else.

**Files:**
- Create: `DictadoSwift/whisper-bridging.h`
- Create: `DictadoSwift/WhisperEngine.swift`
- Create: `DictadoSwift/tests/test_engine.swift`
- Create: `DictadoSwift/tests/run_tests.sh`

- [ ] **Step 1: Create the bridging header**

`DictadoSwift/whisper-bridging.h`:
```c
#ifndef WHISPER_BRIDGING_H
#define WHISPER_BRIDGING_H
#include "whisper.h"
#endif
```

- [ ] **Step 2: Write `WhisperEngine.swift`**

> Note: the API names below are whisper.cpp's stable public C API. If any symbol/field differs in v1.8.6, confirm against `DictadoSwift/vendor/whisper.cpp/include/whisper.h` (it's cloned) and adjust.

```swift
import Foundation

/// Native Whisper transcription via whisper.cpp (CPU, Intel-friendly).
/// Input contract: 16 kHz, mono, float32 PCM samples.
final class WhisperEngine {
    private var ctx: OpaquePointer?

    init?(modelPath: String) {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = false // Intel: CPU only, no Metal
        ctx = whisper_init_from_file_with_params(modelPath, cparams)
        if ctx == nil { return nil }
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    /// Transcribe samples. `language` nil or "auto" → auto-detect.
    func transcribe(samples: [Float], language: String? = nil) -> String? {
        guard let ctx, !samples.isEmpty else { return nil }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.translate = false
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))

        let lang = (language == nil || language == "auto") ? "auto" : language!
        var output: String?
        lang.withCString { langPtr in
            params.language = langPtr
            params.detect_language = (lang == "auto")
            let rc = samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
            guard rc == 0 else { return }
            var text = ""
            let n = whisper_full_n_segments(ctx)
            for i in 0..<n {
                if let cstr = whisper_full_get_segment_text(ctx, i) {
                    text += String(cString: cstr)
                }
            }
            output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return output
    }
}
```

- [ ] **Step 3: Write the smoke test `tests/test_engine.swift`**

```swift
import Foundation
import AVFoundation

// Reads a 16 kHz mono WAV into [Float] (jfk.wav already is 16k mono).
func loadWavSamples(_ path: String) -> [Float] {
    let url = URL(fileURLWithPath: path)
    guard let file = try? AVAudioFile(forReading: url) else { return [] }
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate,
                            channels: 1, interleaved: false)!
    guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
    do { try file.read(into: buf) } catch { return [] }
    guard let ch = buf.floatChannelData else { return [] }
    return Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
}

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: test_engine <model.bin> <jfk.wav>\n".data(using: .utf8)!)
    exit(2)
}
let modelPath = args[1], wavPath = args[2]

guard let engine = WhisperEngine(modelPath: modelPath) else {
    print("FAIL: could not load model at \(modelPath)"); exit(1)
}
let samples = loadWavSamples(wavPath)
guard !samples.isEmpty else { print("FAIL: no samples from \(wavPath)"); exit(1) }

guard let text = engine.transcribe(samples: samples, language: "en") else {
    print("FAIL: transcribe returned nil"); exit(1)
}
print("Transcription: \(text)")
if text.lowercased().contains("country") {
    print("PASS: test_engine"); exit(0)
} else {
    print("FAIL: expected 'country' in output"); exit(1)
}
```

- [ ] **Step 4: Write `tests/run_tests.sh`** (compiles + runs whichever tests exist so far)

```bash
#!/bin/bash
# Compile and run the Swift test binaries against the vendored whisper.cpp libs.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DS_DIR="$SCRIPT_DIR/.."
VENDOR="$DS_DIR/vendor/whisper.cpp"
SDK="$(xcrun --show-sdk-path)"
ARCH="x86_64"; [ "$(uname -m)" = "arm64" ] && ARCH="arm64"
TARGET="${ARCH}-apple-macosx13.0"
OUT="$SCRIPT_DIR/_bin"; mkdir -p "$OUT"

# Ensure libs are built
"$DS_DIR/scripts/build_whisper_lib.sh" >/dev/null

WLIBS=$(find "$VENDOR/build" -name "*.a")
INCS=(-I "$VENDOR/include" -I "$VENDOR/ggml/include")
COMMON=(-sdk "$SDK" -target "$TARGET" -O -framework Accelerate -framework AVFoundation -lc++)

# Ensure base model present for the engine test
MODEL="$VENDOR/models/ggml-base.bin"
if [ ! -f "$MODEL" ]; then
  echo "📥 Downloading base model for tests..."
  bash "$VENDOR/models/download-ggml-model.sh" base "$VENDOR/models" >/dev/null 2>&1 || \
  bash "$VENDOR/models/download-ggml-model.sh" base >/dev/null 2>&1
fi

FAILED=0

run_test() {
  local name="$1"; shift
  echo "🔨 Building $name ..."
  if swiftc "${COMMON[@]}" "${INCS[@]}" -import-objc-header "$DS_DIR/whisper-bridging.h" \
       "$@" $WLIBS -o "$OUT/$name"; then
    echo "▶️  Running $name ..."
    "$OUT/$name" "${TEST_ARGS[@]}" || FAILED=1
  else
    echo "❌ build failed: $name"; FAILED=1
  fi
}

# test_engine needs model + wav as args
TEST_ARGS=("$MODEL" "$VENDOR/samples/jfk.wav")
run_test test_engine "$DS_DIR/WhisperEngine.swift" "$SCRIPT_DIR/test_engine.swift"

exit $FAILED
```

- [ ] **Step 5: Run the smoke test**

Run:
```bash
chmod +x DictadoSwift/tests/run_tests.sh
DictadoSwift/tests/run_tests.sh
```
Expected: prints a JFK transcription line and `PASS: test_engine`, exit 0. If linking fails on missing symbols, confirm the `.a` set from Task 1 Step 4 and the include paths; if a whisper API symbol mismatches, check `vendor/whisper.cpp/include/whisper.h`.

- [ ] **Step 6: Commit**

```bash
git add DictadoSwift/whisper-bridging.h DictadoSwift/WhisperEngine.swift DictadoSwift/tests/test_engine.swift DictadoSwift/tests/run_tests.sh
git commit -m "feat: native WhisperEngine over whisper.cpp + passing integration smoke test"
```

---

## Task 3: AudioRecorder (16 kHz mono float32 capture)

**Files:**
- Create: `DictadoSwift/AudioRecorder.swift`
- Create: `DictadoSwift/tests/test_audio.swift`
- Modify: `DictadoSwift/tests/run_tests.sh` (add test_audio)

- [ ] **Step 1: Write the failing test `tests/test_audio.swift`**

```swift
import Foundation
import AVFoundation

// Build a 48 kHz mono sine buffer, convert via AudioRecorder's resampler helper, expect ~16 kHz count.
let srcRate = 48000.0
let seconds = 1.0
let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: srcRate, channels: 1, interleaved: false)!
let frames = AVAudioFrameCount(srcRate * seconds)
let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frames)!
srcBuf.frameLength = frames
for i in 0..<Int(frames) {
    srcBuf.floatChannelData![0][i] = sinf(Float(2.0 * Double.pi * 440.0 * Double(i) / srcRate))
}

let out = AudioRecorder.resampleToWhisperFormat(srcBuf)
let expected = Int(16000.0 * seconds)
// Allow small boundary slack from the converter.
if out.count > expected - 800 && out.count < expected + 800 {
    print("PASS: test_audio (got \(out.count) samples ~ \(expected))"); exit(0)
} else {
    print("FAIL: expected ~\(expected) samples, got \(out.count)"); exit(1)
}
```

- [ ] **Step 2: Write `AudioRecorder.swift`** (with a testable static `resampleToWhisperFormat`)

```swift
import AVFoundation

/// Captures microphone audio and yields 16 kHz mono float32 samples for whisper.cpp.
final class AudioRecorder {
    static let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16000, channels: 1, interleaved: false)!

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private(set) var isRecording = false

    func start() throws {
        samples.removeAll()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.samples.append(contentsOf: AudioRecorder.resampleToWhisperFormat(buffer))
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    @discardableResult
    func stop() -> [Float] {
        guard isRecording else { return samples }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        return samples
    }

    /// Convert an arbitrary PCM buffer to 16 kHz mono float32 samples. Pure + testable.
    static func resampleToWhisperFormat(_ buffer: AVAudioPCMBuffer) -> [Float] {
        if buffer.format == whisperFormat, let ch = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: whisperFormat) else { return [] }
        let ratio = whisperFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard let ch = outBuffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(outBuffer.frameLength)))
    }
}
```

- [ ] **Step 3: Add test_audio to `tests/run_tests.sh`**

Add before the final `exit $FAILED` (test_audio needs no args and no whisper libs, but linking them is harmless):
```bash
TEST_ARGS=()
run_test test_audio "$DS_DIR/AudioRecorder.swift" "$SCRIPT_DIR/test_audio.swift"
```

- [ ] **Step 4: Run tests**

Run: `DictadoSwift/tests/run_tests.sh`
Expected: `PASS: test_audio` and still `PASS: test_engine`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add DictadoSwift/AudioRecorder.swift DictadoSwift/tests/test_audio.swift DictadoSwift/tests/run_tests.sh
git commit -m "feat: AudioRecorder with 16kHz mono resampling + test"
```

---

## Task 4: ModelManager (catalog + download with progress)

**Files:**
- Create: `DictadoSwift/ModelManager.swift`
- Create: `DictadoSwift/tests/test_modelmanager.swift`
- Modify: `DictadoSwift/tests/run_tests.sh` (add test_modelmanager)

- [ ] **Step 1: Write `ModelManager.swift`**

```swift
import Foundation
import Combine

struct WhisperModelInfo: Identifiable, Equatable {
    let id: String          // "tiny", "base", ...
    let displayName: String // UI label (Spanish)
    let approxBytes: Int64   // for progress total fallback + integrity sanity
    var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(id).bin")! }
}

enum ModelState: Equatable {
    case notDownloaded
    case downloading(fraction: Double, detail: String)
    case ready
    case failed(String)
}

final class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()

    static let catalog: [WhisperModelInfo] = [
        .init(id: "tiny",     displayName: "Tiny (~75 MB - rápido)",        approxBytes: 77_700_000),
        .init(id: "base",     displayName: "Base (~142 MB - equilibrado)",  approxBytes: 147_950_000),
        .init(id: "small",    displayName: "Small (~466 MB - preciso)",     approxBytes: 487_600_000),
        .init(id: "medium",   displayName: "Medium (~1.5 GB - muy preciso)",approxBytes: 1_533_760_000),
        .init(id: "large-v3", displayName: "Large v3 (~2.9 GB - máximo)",   approxBytes: 3_094_620_000),
    ]

    @Published private(set) var states: [String: ModelState] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]

    private lazy var session: URLSession =
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    static var modelsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DictadoWhisper/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func localPath(for id: String) -> URL { Self.modelsDir.appendingPathComponent("ggml-\(id).bin") }

    func info(for id: String) -> WhisperModelInfo? { Self.catalog.first { $0.id == id } }

    /// A model is ready if the file exists and is at least 80% of the expected size (integrity sanity).
    func isReady(_ id: String) -> Bool {
        guard let info = info(for: id) else { return false }
        let path = localPath(for: id).path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return false }
        return size >= Int64(Double(info.approxBytes) * 0.8)
    }

    func refreshState(_ id: String) {
        DispatchQueue.main.async { self.states[id] = self.isReady(id) ? .ready : .notDownloaded }
    }

    /// Download the model if not ready. Triggered when the user selects a model.
    func ensureDownloaded(_ id: String) {
        if isReady(id) { refreshState(id); return }
        guard let info = info(for: id), tasks[id] == nil else { return }
        // Remove a partial file before re-downloading.
        try? FileManager.default.removeItem(at: localPath(for: id))
        DispatchQueue.main.async { self.states[id] = .downloading(fraction: 0, detail: "Iniciando…") }
        let task = session.downloadTask(with: info.url)
        task.taskDescription = id
        tasks[id] = task
        task.resume()
    }

    static func progressDetail(written: Int64, total: Int64) -> (Double, String) {
        let mb = 1_048_576.0
        if total > 0 {
            let frac = Double(written) / Double(total)
            return (frac, String(format: "%d%% (%.0f/%.0f MB)", Int(frac * 100), Double(written)/mb, Double(total)/mb))
        }
        return (0, String(format: "%.0f MB", Double(written)/mb))
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = t.taskDescription else { return }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (info(for: id)?.approxBytes ?? 0)
        let (frac, detail) = Self.progressDetail(written: totalBytesWritten, total: total)
        DispatchQueue.main.async { self.states[id] = .downloading(fraction: frac, detail: detail) }
    }

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = t.taskDescription else { return }
        let dest = localPath(for: id)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.moveItem(at: location, to: dest) }
        catch { DispatchQueue.main.async { self.states[id] = .failed("No se pudo guardar el modelo") }; return }
        tasks[id] = nil
        if isReady(id) { refreshState(id) }
        else { try? FileManager.default.removeItem(at: dest); DispatchQueue.main.async { self.states[id] = .failed("Descarga incompleta") } }
    }

    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = t.taskDescription else { return }
        tasks[id] = nil
        if let error { DispatchQueue.main.async { self.states[id] = .failed(error.localizedDescription) } }
    }
}
```

- [ ] **Step 2: Write `tests/test_modelmanager.swift`** (pure logic — no network)

```swift
import Foundation

var failed = false
func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); failed = true } }

// Progress math with known total.
let (f1, d1) = ModelManager.progressDetail(written: 71_000_000, total: 142_000_000)
check(abs(f1 - 0.5) < 0.02, "fraction ~0.5, got \(f1)")
check(d1.contains("50%"), "detail shows 50%, got \(d1)")
check(d1.contains("MB"), "detail shows MB, got \(d1)")

// Unknown total → fraction 0, still shows MB.
let (f2, d2) = ModelManager.progressDetail(written: 10_485_760, total: 0)
check(f2 == 0, "unknown total → fraction 0")
check(d2.contains("MB"), "unknown total still shows MB, got \(d2)")

// Catalog has base default and builds correct URL.
let base = ModelManager.catalog.first { $0.id == "base" }
check(base != nil, "catalog has base")
check(base?.url.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
      "base URL correct, got \(base?.url.absoluteString ?? "nil")")

if failed { exit(1) } else { print("PASS: test_modelmanager"); exit(0) }
```

- [ ] **Step 3: Add to `tests/run_tests.sh`**

```bash
TEST_ARGS=()
run_test test_modelmanager "$DS_DIR/ModelManager.swift" "$SCRIPT_DIR/test_modelmanager.swift"
```

- [ ] **Step 4: Run tests**

Run: `DictadoSwift/tests/run_tests.sh`
Expected: `PASS: test_modelmanager` plus the previous passes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add DictadoSwift/ModelManager.swift DictadoSwift/tests/test_modelmanager.swift DictadoSwift/tests/run_tests.sh
git commit -m "feat: ModelManager with download progress + integrity check + tests"
```

---

## Task 5: SettingsManager — drop Python config, new engine values

**Files:**
- Modify: `DictadoSwift/SettingsManager.swift`

- [ ] **Step 1: Change defaults and remove the Python bridge**

In `SettingsManager.swift`:
- Change `engine` default from `"apple"` to `"whisper"` (line ~64: `?? "apple"` → `?? "whisper"`). If a previously-saved value is `"whisper_python"`, migrate it: after reading, `if self.engine == "whisper_python" { self.engine = "whisper" }`.
- In `whisperModel` `didSet` and `language`/`playSounds` `didSet`, **remove** the `saveToPythonConfig()` calls.
- **Delete** the entire `saveToPythonConfig()` method.
- Remove the `saveToPythonConfig()` call at the end of `init()`.

Concretely, the `init()` tail becomes:
```swift
        if UserDefaults.standard.object(forKey: "hotkeyCode") == nil {
            self.hotkeyCode = 15
            self.hotkeyModifiers = 6144
        } else {
            self.hotkeyCode = UserDefaults.standard.integer(forKey: "hotkeyCode")
            self.hotkeyModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        }

        // Migrate the removed Python engine to native Whisper.
        if self.engine == "whisper_python" {
            self.engine = "whisper"
        }
    }
```

And each affected `didSet` keeps only its `UserDefaults` write + `NotificationCenter.post`, e.g.:
```swift
    @Published var whisperModel: String {
        didSet {
            UserDefaults.standard.set(whisperModel, forKey: "whisperModel")
            NotificationCenter.default.post(name: .whisperSettingsChanged, object: nil)
        }
    }
```

- [ ] **Step 2: Change `whisperModel` default to base**

Line ~65: `?? "tiny"` → `?? "base"`.

- [ ] **Step 3: Verify it still type-checks**

Run:
```bash
cd DictadoSwift && swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target x86_64-apple-macosx13.0 SettingsManager.swift 2>&1 | head -20; echo "exit ${pipestatus[1]}"
```
Expected: no output, exit 0. (Note: `saveToPythonConfig` removal must leave no callers — grep `grep -n saveToPythonConfig DictadoSwift/*.swift` returns nothing.)

- [ ] **Step 4: Commit**

```bash
git add DictadoSwift/SettingsManager.swift
git commit -m "refactor: SettingsManager drops Python config bridge, defaults to native whisper/base"
```

---

## Task 6: SpeechManager — remove Python, wire Whisper, fix Apple bugs

**Files:**
- Modify: `DictadoSwift/SpeechManager.swift`

- [ ] **Step 1: Remove ALL Python code**

Delete these members/methods entirely: `pythonProcess`, `launchPythonApp()`, `terminatePythonProcess()`, `restartPythonProcess()`, `getPythonPath()`. In `handleSettingsChanged()` remove the Python restart/terminate logic (keep only re-setup of the recognizer if needed). In `init()` remove the `if SettingsManager.shared.engine == "whisper_python" { launchPythonApp() }` block. In `startRecording()` remove the `if engine == "whisper_python" { launchPythonApp(); return }` block. Update `AppDelegate.applicationWillTerminate` (in `DictadoWhisperApp.swift`) to drop the `terminatePythonProcess()` call.

- [ ] **Step 2: Add Whisper engine members and routing**

Add properties:
```swift
    private let audioRecorder = AudioRecorder()
    private var whisperEngine: WhisperEngine?
    private var loadedModelId: String?
```

Make `startRecording()` route by engine. Apple path stays as-is (with the fix in Step 3). Whisper path:
```swift
    func startRecording() {
        guard !isRecording else { return }
        capturePreviousApp() // existing focus-saving logic, extracted into a helper

        if SettingsManager.shared.engine == "whisper" {
            startWhisperRecording()
            return
        }
        startAppleRecording() // existing SFSpeechRecognizer setup
    }

    private func startWhisperRecording() {
        let modelId = SettingsManager.shared.whisperModel
        guard ModelManager.shared.isReady(modelId) else {
            updateStatus("⬇️ Descarga el modelo primero (ajustes)", play: "Basso")
            ModelManager.shared.ensureDownloaded(modelId)
            return
        }
        do {
            try audioRecorder.start()
            isRecording = true
            currentTranscription = ""
            updateStatus("🎤 Grabando...", play: "Tink")
        } catch {
            updateStatus("❌ Error de micrófono", play: "Basso")
        }
    }
```

`stopRecording()` routes too:
```swift
    func stopRecording() {
        guard isRecording else { return }
        if SettingsManager.shared.engine == "whisper" { stopWhisperRecording(); return }
        stopAppleRecording() // existing flow, with Step 3 fix
    }

    private func stopWhisperRecording() {
        isRecording = false
        updateStatus("⌛ Transcribiendo...", play: "Ping")
        let samples = audioRecorder.stop()
        DispatchQueue.main.async {
            if let d = NSApplication.shared.delegate as? AppDelegate { d.closePopover(nil) }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let modelId = SettingsManager.shared.whisperModel
            if self.whisperEngine == nil || self.loadedModelId != modelId {
                self.whisperEngine = WhisperEngine(modelPath: ModelManager.shared.localPath(for: modelId).path)
                self.loadedModelId = modelId
            }
            let text = self.whisperEngine?.transcribe(samples: samples, language: "auto")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                if text.isEmpty {
                    self.updateStatus("⚠️ No se detectó voz", play: "Pop")
                } else {
                    self.currentTranscription = text
                    self.updateStatus("✍️ Transcrito: \"\(text.prefix(30))...\"", play: "Glass")
                    self.copyAndPasteText(text)
                    HistoryManager.shared.addEntry(text: text)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if !self.isRecording { self.statusText = "Listo" }
                }
            }
        }
    }
```

> Extract the existing focus-saving block at the top of the old `startRecording()` into `capturePreviousApp()`, and rename the existing Apple setup into `startAppleRecording()` / `stopAppleRecording()`. The `copyAndPasteText`, `previousApp`, `updateStatus`, `playGuideSound` logic is reused unchanged.

- [ ] **Step 3: Fix the two Apple-engine bugs**

In `stopAppleRecording()` (the former `stopRecording` body), replace the blind `asyncAfter(deadline: .now() + 1.0)` with waiting for the recognizer's final result. Track an `isFinalReceived` flag set in the recognition callback when `result.isFinal`; in the callback's final branch, trigger the paste. Keep a 3 s safety timeout that fires the same paste path if `isFinal` never arrives:
```swift
    // in the recognitionTask callback, replace the `if error != nil || isFinal { ... }` cleanup block tail:
    if error != nil || isFinal {
        self.audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        self.recognitionRequest = nil
        self.recognitionTask = nil
        if isFinal { DispatchQueue.main.async { self.finishAppleTranscription() } }
    }
```
And `stopAppleRecording()` becomes:
```swift
    private func stopAppleRecording() {
        guard isRecording else { return }
        isRecording = false
        updateStatus("⌛ Transcribiendo...", play: "Ping")
        DispatchQueue.main.async {
            if let d = NSApplication.shared.delegate as? AppDelegate { d.closePopover(nil) }
        }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        // Safety net: if isFinal never arrives within 3s, finish with whatever we have.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, !self.finishedThisRound else { return }
            self.finishAppleTranscription()
        }
    }

    private var finishedThisRound = false
    private func finishAppleTranscription() {
        guard !finishedThisRound else { return }
        finishedThisRound = true
        let text = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            updateStatus("✍️ Transcrito: \"\(text.prefix(30))...\"", play: "Glass")
            copyAndPasteText(text)
            HistoryManager.shared.addEntry(text: text)
        } else {
            updateStatus("⚠️ No se detectó voz", play: "Pop")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if !self.isRecording { self.statusText = "Listo" }
        }
    }
```
Reset `finishedThisRound = false` at the start of `startAppleRecording()`.

In `setupRecognizer()` / `startAppleRecording()`, guard on-device support:
```swift
    guard let recognizer = speechRecognizer, recognizer.isAvailable else {
        updateStatus("❌ Motor de voz no disponible", play: "Basso"); return
    }
    if !recognizer.supportsOnDeviceRecognition {
        updateStatus("⚠️ Este idioma no soporta dictado local de Apple. Usa Whisper.", play: "Basso"); return
    }
```

- [ ] **Step 4: Verify type-check of the whole app**

Run:
```bash
cd DictadoSwift && swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target x86_64-apple-macosx13.0 \
  -import-objc-header whisper-bridging.h -I vendor/whisper.cpp/include -I vendor/whisper.cpp/ggml/include \
  *.swift 2>&1 | head -40; echo "exit ${pipestatus[1]}"
```
Expected: exit 0, no errors. Confirm no Python remains: `grep -rn "python\|Python\|pynput\|launchPythonApp" DictadoSwift/*.swift` → only comments/none.

- [ ] **Step 5: Commit**

```bash
git add DictadoSwift/SpeechManager.swift DictadoSwift/DictadoWhisperApp.swift
git commit -m "refactor: SpeechManager runs Whisper in-process, removes Python, fixes Apple isFinal/on-device bugs"
```

---

## Task 7: ContentView — engine/model pickers, download progress, auto language

**Files:**
- Modify: `DictadoSwift/ContentView.swift`

- [ ] **Step 1: Replace the engine picker options**

Change the engine `Picker` (the "Motor" section) tags from `"apple"`/`"whisper_python"` to:
```swift
                        Picker("", selection: $settings.engine) {
                            Text("Whisper Local").tag("whisper")
                            Text("Apple Local").tag("apple")
                        }
```

- [ ] **Step 2: Replace the Whisper model section with catalog + progress**

Replace the `if settings.engine == "whisper_python"` block with `if settings.engine == "whisper"`, drive the picker from `ModelManager.catalog`, and add a progress row. Add `@ObservedObject private var models = ModelManager.shared` to the view. On model change and on appear, call `models.ensureDownloaded(...)`.
```swift
                    if settings.engine == "whisper" {
                        Divider().background(surfaceColor.opacity(0.3))
                        HStack {
                            Text("Modelo:").font(.system(size: 14, weight: .bold)).foregroundColor(textColor)
                            Spacer()
                            Picker("", selection: $settings.whisperModel) {
                                ForEach(ModelManager.catalog) { m in Text(m.displayName).tag(m.id) }
                            }
                            .pickerStyle(MenuPickerStyle()).frame(width: 195).labelsHidden()
                            .onChange(of: settings.whisperModel) { _, newId in models.ensureDownloaded(newId) }
                        }
                        whisperModelStatusRow
                    }
```
Add this computed view to `ContentView`:
```swift
    @ViewBuilder private var whisperModelStatusRow: some View {
        let state = models.states[settings.whisperModel] ?? (models.isReady(settings.whisperModel) ? .ready : .notDownloaded)
        switch state {
        case .ready:
            Label("Modelo listo", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundColor(greenColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .downloading(let fraction, let detail):
            VStack(alignment: .leading, spacing: 3) {
                Text("Descargando modelo… \(detail)").font(.system(size: 11)).foregroundColor(yellowColor)
                ProgressView(value: fraction).tint(lavenderColor)
            }
        case .notDownloaded:
            Button("Descargar modelo") { models.ensureDownloaded(settings.whisperModel) }
                .font(.system(size: 11, weight: .bold)).foregroundColor(lavenderColor)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 3) {
                Text("❌ \(msg)").font(.system(size: 11)).foregroundColor(redColor)
                Button("Reintentar") { models.ensureDownloaded(settings.whisperModel) }
                    .font(.system(size: 11, weight: .bold)).foregroundColor(lavenderColor)
            }
        }
    }
```
In `.onAppear` (body), refresh + auto-start download of the selected model when on the whisper engine:
```swift
        .onAppear {
            speechManager.checkAccessibilityPermissions()
            if settings.engine == "whisper" { models.ensureDownloaded(settings.whisperModel) }
        }
```

- [ ] **Step 3: Add "Automático" to the language list**

In the `languages` array, the Whisper engine uses auto-detection, so the language picker is only meaningful for Apple. Hide the language row when `settings.engine == "whisper"` (Whisper auto-detects). Wrap the existing language `HStack` + its `Divider` in `if settings.engine == "apple" { ... }`.

- [ ] **Step 4: Type-check**

Run:
```bash
cd DictadoSwift && swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target x86_64-apple-macosx13.0 \
  -import-objc-header whisper-bridging.h -I vendor/whisper.cpp/include -I vendor/whisper.cpp/ggml/include \
  *.swift 2>&1 | head -40; echo "exit ${pipestatus[1]}"
```
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add DictadoSwift/ContentView.swift
git commit -m "feat: ContentView native-whisper UI — model catalog, download progress bar, auto language"
```

---

## Task 8: build.sh — compile + link the app with whisper.cpp

**Files:**
- Modify: `DictadoSwift/build.sh`

- [ ] **Step 1: Build the whisper lib first, then link it into the app**

At the top of `build.sh` (after the dir setup), add:
```bash
echo "🧱 Building whisper.cpp static libs..."
"$(dirname "$0")/scripts/build_whisper_lib.sh"
VENDOR="$(dirname "$0")/vendor/whisper.cpp"
WLIBS=$(find "$VENDOR/build" -name "*.a")
```
Change the `swiftc` invocation to add the bridging header, include paths, the libs, and frameworks:
```bash
swiftc -o "$MACOS_DIR/DictadoWhisper" \
    -sdk "$SDK_PATH" \
    -target "${ARCH}-apple-macosx13.0" \
    -O \
    -import-objc-header "$(dirname "$0")/whisper-bridging.h" \
    -I "$VENDOR/include" -I "$VENDOR/ggml/include" \
    -framework Accelerate -framework AVFoundation -lc++ \
    DictadoWhisperApp.swift \
    ContentView.swift \
    SpeechManager.swift \
    HotkeyManager.swift \
    SettingsManager.swift \
    HistoryManager.swift \
    WhisperEngine.swift \
    AudioRecorder.swift \
    ModelManager.swift \
    $WLIBS
```

- [ ] **Step 2: Run the full build**

Run: `cd DictadoSwift && ./build.sh`
Expected: compiles, codesigns, installs to `/Applications`, opens the app. No linker errors. App icon appears in the menu bar.

- [ ] **Step 3: Verify the app launched and is signed**

Run:
```bash
codesign -dv "/Applications/Dictado Whisper.app" 2>&1 | head -3
pgrep -fl "Dictado Whisper" || echo "(not running)"
```
Expected: signature info prints; process is running.

- [ ] **Step 4: Commit**

```bash
git add DictadoSwift/build.sh
git commit -m "build: link whisper.cpp into the app bundle"
```

---

## Task 9: Delete Python, rewrite install docs

**Files:**
- Delete: `dictado_whisper.py`, `build_app.py`, `setup.sh`, `config.json`, `__pycache__/`
- Move: `Guia_Resolucion_Problemas.md` → `docs/legacy/Guia_Resolucion_Problemas.md`
- Rewrite: `install.md`
- Modify: `CLAUDE.md` (remove the two-implementation / Python sections, describe the native build)

- [ ] **Step 1: Remove the Python files**

Run:
```bash
git rm dictado_whisper.py build_app.py setup.sh config.json
rm -rf __pycache__
mkdir -p docs/legacy && git mv Guia_Resolucion_Problemas.md docs/legacy/Guia_Resolucion_Problemas.md
```

- [ ] **Step 2: Rewrite `install.md`** for the native app

```markdown
# Dictado Whisper — Instalación (app nativa)

App de dictado por voz para macOS. Motor por defecto: **Whisper nativo** (whisper.cpp, multidioma con auto-detección). Motor alterno: **Apple** (dictado local del sistema).

## Requisitos
- macOS 13+ (Intel o Apple Silicon).
- Command Line Tools (`xcode-select --install`) y `cmake` (`brew install cmake`).

## Compilar e instalar
```bash
cd DictadoSwift
./build.sh
```
La primera compilación clona y compila whisper.cpp (~1–2 min). Las siguientes son rápidas. La app se instala en `/Applications` y arranca en la barra de menús.

## Primer uso
1. **Micrófono**: acepta el permiso al primer dictado.
2. **Accesibilidad** (para pegar con Cmd+V): Configuración del Sistema → Privacidad y Seguridad → Accesibilidad → activa "Dictado Whisper".
3. **Modelo Whisper**: abre el panel (ícono de micrófono), elige el modelo (por defecto `base`, ~142 MB). Se descarga mostrando una barra de progreso. Una vez descargado, funciona 100% offline.

## Uso
- Coloca el cursor donde quieras escribir.
- Pulsa el atajo global (por defecto ⌃⌥R) para empezar/parar. El texto se transcribe y se pega solo.
```

- [ ] **Step 3: Update `CLAUDE.md`** — replace the "two parallel implementations" framing with the native architecture (Swift + whisper.cpp, no Python). Remove the Python build/commands and the bridge section; keep the macOS-constraint notes that still apply (PATH/threading no longer relevant to a deleted script — drop those; keep Accessibility/quarantine/codesign). Point the build at `DictadoSwift/build.sh` and note the cmake/whisper.cpp dependency.

- [ ] **Step 4: Verify no Python references remain in code/build**

Run:
```bash
grep -rn "dictado_whisper.py\|build_app.py\|whisper_python\|pynput" --include="*.swift" --include="*.sh" --include="*.md" . | grep -v docs/legacy | grep -v docs/superpowers || echo "clean"
ls dictado_whisper.py build_app.py setup.sh config.json 2>&1
```
Expected: "clean" (or only legacy/spec mentions); the `ls` reports the files are gone.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove Python implementation, rewrite install docs for native app"
```

---

## Task 10: End-to-end verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `DictadoSwift/tests/run_tests.sh`
Expected: `PASS: test_engine`, `PASS: test_audio`, `PASS: test_modelmanager`, exit 0.

- [ ] **Step 2: Fresh build from clean**

Run:
```bash
rm -rf DictadoSwift/build && cd DictadoSwift && ./build.sh
```
Expected: app builds, installs, launches.

- [ ] **Step 3: Manual smoke (record in the report what was actually observed)**

Checklist to verify by hand and report honestly (do not claim PASS without observing):
1. Menu-bar icon turns red/recording when the hotkey is pressed (both engines).
2. Whisper engine: with `base` downloaded, dictate a Spanish sentence → it pastes at the cursor.
3. Whisper auto-detect: dictate an English sentence **without** changing settings → recognized correctly.
4. Selecting a not-yet-downloaded model shows the progress bar advancing (no frozen UI).
5. Apple engine: switch to Apple, dictate, verify paste; long (>15 s) dictation isn't truncated (isFinal fix).
6. No second window / no Python process ever appears: `pgrep -fl python` shows nothing related.

- [ ] **Step 4: Final commit + push**

```bash
git add -A && git commit -m "test: end-to-end verification of native whisper engine" --allow-empty
git push origin main
```

---

## Self-Review Notes (filled by planner)

- **Spec coverage:** native whisper (T2), multi-language auto (T2 `language:"auto"`, T6/T7 wiring), download progress (T4 + T7 bar), keep Apple (T6 routing), remove Python (T9), build integration (T1/T8), Apple bug fixes (T6 Step 3), testing (T2/T3/T4/T10). All spec sections map to tasks.
- **Library-name risk** is handled by `find ... -name "*.a"` instead of hardcoded `-l` flags.
- **whisper.h API symbols** are confirmable against the cloned header in T2.
- **Type names** are consistent across tasks: `WhisperEngine`, `AudioRecorder.resampleToWhisperFormat`, `ModelManager.{catalog,states,ensureDownloaded,isReady,localPath,progressDetail}`, `ModelState`, `WhisperModelInfo`.
