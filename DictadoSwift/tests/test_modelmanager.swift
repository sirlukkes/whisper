import Foundation

// `@main` entry point: when compiling multiple Swift files together, top-level
// statements are only allowed in a file named `main.swift`, so this test uses an
// explicit entry point instead.
@main
enum TestModelManager {
    static func main() {
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

        // Catalog has base entry and builds correct URL.
        let base = ModelManager.catalog.first { $0.id == "base" }
        check(base != nil, "catalog has base")
        check(base?.url.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
              "base URL correct, got \(base?.url.absoluteString ?? "nil")")

        if failed { exit(1) } else { print("PASS: test_modelmanager"); exit(0) }
    }
}
