import Foundation

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "language")
            saveToPythonConfig()
            NotificationCenter.default.post(name: .whisperSettingsChanged, object: nil)
        }
    }
    
    @Published var playSounds: Bool {
        didSet {
            UserDefaults.standard.set(playSounds, forKey: "playSounds")
            saveToPythonConfig()
            NotificationCenter.default.post(name: .whisperSettingsChanged, object: nil)
        }
    }
    
    @Published var hotkeyCode: Int {
        didSet {
            UserDefaults.standard.set(hotkeyCode, forKey: "hotkeyCode")
            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
        }
    }
    
    @Published var hotkeyModifiers: Int {
        didSet {
            UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers")
            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
        }
    }
    
    @Published var theme: String {
        didSet {
            UserDefaults.standard.set(theme, forKey: "theme")
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }
    
    @Published var engine: String {
        didSet {
            UserDefaults.standard.set(engine, forKey: "engine")
            NotificationCenter.default.post(name: .whisperSettingsChanged, object: nil)
        }
    }
    
    @Published var whisperModel: String {
        didSet {
            UserDefaults.standard.set(whisperModel, forKey: "whisperModel")
            saveToPythonConfig()
            NotificationCenter.default.post(name: .whisperSettingsChanged, object: nil)
        }
    }
    
    private init() {
        // Defaults: Spanish (es-ES), playSounds = true
        self.language = UserDefaults.standard.string(forKey: "language") ?? "es-ES"
        self.playSounds = UserDefaults.standard.object(forKey: "playSounds") as? Bool ?? true
        
        self.theme = UserDefaults.standard.string(forKey: "theme") ?? "system"
        self.engine = UserDefaults.standard.string(forKey: "engine") ?? "apple"
        self.whisperModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "tiny"
        
        // Keycode 15 is virtual key code for 'R'
        // Modifiers 6144 is controlKey (4096) + optionKey (2048)
        if UserDefaults.standard.object(forKey: "hotkeyCode") == nil {
            self.hotkeyCode = 15
            self.hotkeyModifiers = 6144
        } else {
            self.hotkeyCode = UserDefaults.standard.integer(forKey: "hotkeyCode")
            self.hotkeyModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        }
        
        // Sincronizar en el arranque
        saveToPythonConfig()
    }
    
    func saveToPythonConfig() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let configFileURL = homeDir.appendingPathComponent(".dictado_whisper_config.json")
        
        var config: [String: Any] = [:]
        
        if fileManager.fileExists(atPath: configFileURL.path) {
            if let data = try? Data(contentsOf: configFileURL),
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                config = json
            }
        }
        
        let swiftLang = self.language
        let pyLang = String(swiftLang.prefix(2))
        
        config["model_size"] = self.whisperModel
        config["language"] = pyLang
        config["play_sounds"] = self.playSounds
        
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try data.write(to: configFileURL)
            print("Configuración de Python sincronizada en: \(configFileURL.path)")
        } catch {
            print("Error al guardar la configuración de Python: \(error.localizedDescription)")
        }
    }
    
    // Help helper to return hotkey description
    var hotkeyDescription: String {
        var parts: [String] = []
        let mods = hotkeyModifiers
        
        if (mods & 4096) != 0 { parts.append("⌃ Control") }
        if (mods & 2048) != 0 { parts.append("⌥ Option") }
        if (mods & 512) != 0 { parts.append("⇧ Shift") }
        if (mods & 256) != 0 { parts.append("⌘ Command") }
        
        parts.append(keyName(for: hotkeyCode))
        return parts.joined(separator: " + ")
    }
    
    private func keyName(for code: Int) -> String {
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Enter"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Espacio"
        case 50: return "`"
        case 51: return "Borrar"
        case 53: return "Escape"
        case 115: return "Inicio (Home)"
        case 116: return "RePág (PageUp)"
        case 117: return "Suprimir"
        case 119: return "Fin (End)"
        case 121: return "AvPág (PageDown)"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 123: return "← Flecha Izquierda"
        case 124: return "→ Flecha Derecha"
        case 125: return "↓ Flecha Abajo"
        case 126: return "↑ Flecha Arriba"
        default: return "Tecla \(code)"
        }
    }
}

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
    static let themeChanged = Notification.Name("themeChanged")
    static let whisperSettingsChanged = Notification.Name("whisperSettingsChanged")
}
