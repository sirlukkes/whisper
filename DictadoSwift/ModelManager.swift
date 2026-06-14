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
        .init(id: "tiny",     displayName: "Tiny (~75 MB - rápido)",         approxBytes: 77_700_000),
        .init(id: "base",     displayName: "Base (~142 MB - equilibrado)",   approxBytes: 147_950_000),
        .init(id: "small",    displayName: "Small (~466 MB - preciso)",      approxBytes: 487_600_000),
        .init(id: "medium",   displayName: "Medium (~1.5 GB - muy preciso)", approxBytes: 1_533_760_000),
        .init(id: "large-v3", displayName: "Large v3 (~2.9 GB - máximo)",    approxBytes: 3_094_620_000),
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
