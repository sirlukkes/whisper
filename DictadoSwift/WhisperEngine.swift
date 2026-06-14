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
