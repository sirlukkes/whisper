import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Inicializar el HotkeyManager para registrar el atajo global Carbon
        _ = HotkeyManager.shared
        
        // Crear el Popover que contiene nuestra vista SwiftUI
        popover.contentSize = NSSize(width: 380, height: 450)
        popover.behavior = .transient // Se cierra al hacer clic fuera
        popover.contentViewController = NSHostingController(rootView: ContentView(speechManager: SpeechManager.shared))
        
        // Registrar item en la barra de menús del sistema
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictado Whisper")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // Escuchar el estado de grabación para cambiar el ícono y color en la barra de menús
        NotificationCenter.default.addObserver(self, selector: #selector(recordingStateChanged), name: .recordingStateChanged, object: nil)
        
        // Mostrar la ventana automáticamente al abrir por primera vez para guiar al usuario
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.showPopover()
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }
    
    func showPopover(_ sender: AnyObject? = nil) {
        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Traer la aplicación al frente para que los cuadros de texto reciban el foco y funcionen los atajos
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }
    
    @objc func recordingStateChanged() {
        guard let button = statusItem?.button else { return }
        let manager = SpeechManager.shared
        
        DispatchQueue.main.async {
            if manager.isRecording {
                // Al grabar: Cambiar ícono, añadir texto de aviso en rojo y teñir el botón
                button.image = NSImage(systemSymbolName: "mic.and.signal.meter.fill", accessibilityDescription: "Grabando")
                button.title = " 🔴 GRABANDO"
                button.contentTintColor = NSColor.systemRed
            } else {
                // Al detenerse: Restaurar ícono original y limpiar el texto/color
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictado Whisper")
                button.title = ""
                button.contentTintColor = nil
            }
        }
    }
    
    // Si el usuario hace doble clic en la App en Aplicaciones o en Finder, abrir el panel automáticamente
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // No-op: the Whisper engine runs in-process and needs no external teardown.
    }
}

@main
struct DictadoWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        // Settings escena vacía para que no abra ventanas del Dock y corra 100% de fondo
        Settings {
            EmptyView()
        }
    }
}
