import Foundation
import AVFoundation

// `@main` entry point: when compiling multiple Swift files together, top-level
// statements are only allowed in a file named `main.swift`, so this test uses an
// explicit entry point instead.
@main
enum TestAudio {
    static func main() {
        // Build a 48 kHz mono sine buffer, convert via AudioRecorder's resampler helper,
        // expect ~16 kHz count.
        let srcRate = 48000.0
        let seconds = 1.0
        let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: srcRate, channels: 1, interleaved: false)!
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
    }
}
