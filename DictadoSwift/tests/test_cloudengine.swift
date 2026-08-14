import Foundation

// Offline tests for CloudEngine: WAV encoding + multipart request building.
// No network calls — the transcribe() path is exercised manually against the live API.
@main
enum TestCloudEngine {
    static func main() {
        // 1 second of silence @16 kHz mono PCM16 → 44-byte header + 32000 data bytes.
        let samples = [Float](repeating: 0, count: 16000)
        let wav = CloudEngine.wavData(from: samples)
        guard wav.count == 44 + 32000 else { print("FAIL: wav size \(wav.count)"); exit(1) }
        guard String(data: wav.prefix(4), encoding: .ascii) == "RIFF",
              String(data: wav.subdata(in: 8..<12), encoding: .ascii) == "WAVE",
              String(data: wav.subdata(in: 36..<40), encoding: .ascii) == "data" else {
            print("FAIL: wav header markers"); exit(1)
        }

        // Request: auth header, model field, and the wav payload embedded.
        let p = CloudEngine.provider("groq")
        let req = CloudEngine.buildRequest(provider: p, apiKey: "test-key", wav: wav)
        guard req.value(forHTTPHeaderField: "Authorization") == "Bearer test-key" else {
            print("FAIL: auth header"); exit(1)
        }
        guard let body = req.httpBody,
              let textPrefix = String(data: body.prefix(300), encoding: .utf8),
              textPrefix.contains("whisper-large-v3-turbo") else {
            print("FAIL: model field missing in body"); exit(1)
        }
        guard body.range(of: "RIFF".data(using: .ascii)!) != nil else {
            print("FAIL: wav not embedded in body"); exit(1)
        }

        // Language: omitted by default (auto-detect), included when explicit.
        guard !textPrefix.contains("name=\"language\"") else { print("FAIL: language sent by default"); exit(1) }
        let reqEs = CloudEngine.buildRequest(provider: p, apiKey: "k", wav: wav, language: "es")
        guard let bodyEs = reqEs.httpBody,
              String(data: bodyEs.prefix(400), encoding: .utf8)?.contains("name=\"language\"") == true else {
            print("FAIL: explicit language not sent"); exit(1)
        }

        // Unknown provider id falls back to the first entry (groq).
        guard CloudEngine.provider("nope").id == "groq" else { print("FAIL: provider fallback"); exit(1) }

        print("PASS: test_cloudengine"); exit(0)
    }
}
