import Carbon
import Cocoa

class HotkeyManager {
    static let shared = HotkeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    init() {
        setupEventHandler()
        registerCurrentHotkey()
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .hotkeyChanged, object: nil)
    }
    
    @objc private func settingsChanged() {
        registerCurrentHotkey()
    }
    
    private func setupEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handlerCallback: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            // Carbon callbacks are on main thread, but post notification to be safe
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .globalHotkeyTriggered, object: nil)
            }
            return noErr
        }
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        if status != noErr {
            print("Error al instalar el manejador de eventos Carbon: \(status)")
        }
    }
    
    func registerCurrentHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        
        let code = SettingsManager.shared.hotkeyCode
        let mods = SettingsManager.shared.hotkeyModifiers
        
        // Firma única de 4 letras para identificar nuestro atajo
        let hotKeyID = EventHotKeyID(signature: UTGetOSTypeFromString("DTWS"), id: 1)
        
        let status = RegisterEventHotKey(
            UInt32(code),
            UInt32(mods),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            print("Error al registrar atajo Carbon: \(status)")
        } else {
            print("Atajo registrado con éxito: código \(code), modificadores \(mods)")
        }
    }
}

extension Notification.Name {
    static let globalHotkeyTriggered = Notification.Name("globalHotkeyTriggered")
}

// Ayudante para convertir un string de firma de 4 letras a OSType (UInt32)
func UTGetOSTypeFromString(_ string: String) -> OSType {
    var result: OSType = 0
    let chars = Array(string.utf8)
    for i in 0..<min(4, chars.count) {
        result = (result << 8) + OSType(chars[i])
    }
    return result
}
