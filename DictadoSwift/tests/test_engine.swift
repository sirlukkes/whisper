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

// `@main` entry point: when compiling multiple Swift files together, top-level
// statements are only allowed in a file named `main.swift`, so this test uses an
// explicit entry point instead.
@main
enum TestEngine {
    static func main() {
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

        // Case 1: explicit language "en" must transcribe.
        guard let textEn = engine.transcribe(samples: samples, language: "en") else {
            print("FAIL: transcribe(en) returned nil"); exit(1)
        }
        print("Transcription (en): \(textEn)")
        guard textEn.lowercased().contains("country") else {
            print("FAIL: expected 'country' in 'en' output"); exit(1)
        }

        // Case 2: "auto" is the real dictation path. It must auto-detect the language
        // AND transcribe — not just detect and exit (the detect_language regression).
        guard let textAuto = engine.transcribe(samples: samples, language: "auto") else {
            print("FAIL: transcribe(auto) returned nil"); exit(1)
        }
        print("Transcription (auto): \(textAuto)")
        guard textAuto.lowercased().contains("country") else {
            print("FAIL: 'auto' produced no transcription (detect_language bug)"); exit(1)
        }

        print("PASS: test_engine"); exit(0)
    }
}
