import Foundation

/// Cloud transcription via OpenAI-compatible `/audio/transcriptions` endpoints.
/// Groq and OpenAI share the same multipart contract, so one client covers both.
/// Input contract: 16 kHz mono float32 PCM samples (same as WhisperEngine).
final class CloudEngine {

    struct Provider {
        let id: String           // "groq" | "openai"
        let displayName: String  // UI label
        let endpoint: URL
        let model: String
        let keyConsoleURL: String // where the user creates the API key
    }

    static let providers: [Provider] = [
        .init(id: "groq",
              displayName: "Groq (Whisper v3 Turbo)",
              endpoint: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
              model: "whisper-large-v3-turbo",
              keyConsoleURL: "console.groq.com/keys"),
        .init(id: "openai",
              displayName: "OpenAI (4o-mini)",
              endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
              model: "gpt-4o-mini-transcribe",
              keyConsoleURL: "platform.openai.com/api-keys"),
    ]

    static func provider(_ id: String) -> Provider {
        providers.first { $0.id == id } ?? providers[0]
    }

    /// Encode 16 kHz mono float32 samples as a PCM16 WAV blob (44-byte canonical header).
    static func wavData(from samples: [Float], sampleRate: Int = 16000) -> Data {
        var data = Data(capacity: 44 + samples.count * 2)
        let dataSize = samples.count * 2
        func ascii(_ s: String) { data.append(s.data(using: .ascii)!) }
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(36 + dataSize); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)                 // PCM, mono
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)  // byte rate, block align, bits
        ascii("data"); u32(dataSize)
        for s in samples {
            var v = Int16(max(-1, min(1, s)) * 32767).littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Multipart request. `language` nil → the provider auto-detects (es/en/…).
    static func buildRequest(provider: Provider, apiKey: String, wav: Data, language: String? = nil) -> URLRequest {
        var req = URLRequest(url: provider.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        let boundary = "dictado-\(UUID().uuidString)"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", provider.model)
        field("response_format", "json")
        if let language { field("language", language) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return req
    }

    /// Async transcription. Completion runs on URLSession's queue — hop to main before touching UI.
    func transcribe(samples: [Float], providerId: String, apiKey: String,
                    completion: @escaping (Result<String, CloudEngineError>) -> Void) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { completion(.failure(.missingKey)); return }
        guard !samples.isEmpty else { completion(.success("")); return }
        let provider = Self.provider(providerId)
        let req = Self.buildRequest(provider: provider, apiKey: key, wav: Self.wavData(from: samples))
        URLSession.shared.dataTask(with: req) { data, resp, error in
            if let error { completion(.failure(.network(error.localizedDescription))); return }
            guard let http = resp as? HTTPURLResponse, let data else {
                completion(.failure(.badResponse)); return
            }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 { completion(.failure(.unauthorized)) }
                else { completion(.failure(.http(http.statusCode))) }
                return
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["text"] as? String else {
                completion(.failure(.badResponse)); return
            }
            completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }.resume()
    }
}

enum CloudEngineError: Error {
    case missingKey
    case unauthorized
    case badResponse
    case network(String)
    case http(Int)

    /// Short Spanish message for the status line (UI-facing).
    var userMessage: String {
        switch self {
        case .missingKey:     return "Configura la API key en ajustes"
        case .unauthorized:   return "API key inválida"
        case .badResponse:    return "Respuesta inesperada del servicio"
        case .network:        return "Sin conexión con el servicio"
        case .http(let code): return "Error del servicio (HTTP \(code))"
        }
    }
}
