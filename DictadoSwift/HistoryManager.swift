import Foundation
import Cocoa

struct HistoryEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let text: String
}

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    @Published var entries: [HistoryEntry] = []
    
    private let maxEntries = 50
    private let userDefaultsKey = "transcriptionHistory"
    
    private init() {
        loadHistory()
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            do {
                let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)
                self.entries = decoded
            } catch {
                print("Error cargando historial: \(error)")
            }
        }
    }
    
    private func saveHistory() {
        do {
            let encoded = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        } catch {
            print("Error guardando historial: \(error)")
        }
    }
    
    func addEntry(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let newEntry = HistoryEntry(id: UUID(), date: Date(), text: trimmed)
        
        DispatchQueue.main.async {
            self.entries.insert(newEntry, at: 0)
            
            // Limitar tamaño del historial en la UI
            if self.entries.count > self.maxEntries {
                self.entries = Array(self.entries.prefix(self.maxEntries))
            }
            
            self.saveHistory()
            self.appendToMarkdownFile(text: trimmed)
        }
    }
    
    func clearHistory() {
        DispatchQueue.main.async {
            self.entries.removeAll()
            self.saveHistory()
        }
    }
    
    // Ruta del archivo Markdown en ~/Documents/DictadoWhisper_Historial.md
    var markdownFileUrl: URL? {
        guard let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsUrl.appendingPathComponent("DictadoWhisper_Historial.md")
    }
    
    private func appendToMarkdownFile(text: String) {
        guard let fileUrl = markdownFileUrl else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = formatter.string(from: Date())
        
        let mdSnippet = """
        
        ## [\(dateString)]
        - **Texto:** \(text)
        
        """
        
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            if let fileHandle = try? FileHandle(forWritingTo: fileUrl) {
                fileHandle.seekToEndOfFile()
                if let data = mdSnippet.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            }
        } else {
            let initialContent = """
            # Historial de Transcripciones - Dictado Whisper
            
            Este archivo contiene el historial completo de tus transcripciones locales ordenadas por fecha.
            
            \(mdSnippet)
            """
            try? initialContent.write(to: fileUrl, atomically: true, encoding: .utf8)
        }
    }
    
    func openMarkdownFile() {
        guard let fileUrl = markdownFileUrl else { return }
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            NSWorkspace.shared.open(fileUrl)
        } else {
            // Si no existe, crear uno vacío para poder abrirlo
            let initialContent = "# Historial de Transcripciones - Dictado Whisper\n\nNo hay registros aún.\n"
            try? initialContent.write(to: fileUrl, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileUrl)
        }
    }
}
