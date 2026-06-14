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
