import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Inicializar el HotkeyManager para registrar el atajo global Carbon
        _ = HotkeyManager.shared
        
        // Crear el Popover que contiene nuestra vista SwiftUI
        popover.contentSize = NSSize(width: 380, height: 770)
        popover.behavior = .transient // Se cierra al hacer clic fuera
        popover.contentViewController = NSHostingController(rootView: ContentView(speechManager: SpeechManager.shared))
        
        // Registrar item en la barra de menús del sistema
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: Brand.appName)
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            // Right-click opens the menu; left-click keeps its original behaviour (toggle popover).
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Escuchar el estado de grabación para cambiar el ícono y color en la barra de menús
        NotificationCenter.default.addObserver(self, selector: #selector(recordingStateChanged), name: .recordingStateChanged, object: nil)
        
        // Mostrar la ventana automáticamente al abrir por primera vez para guiar al usuario
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.showPopover()
        }
    }
    
    /// Left-click toggles the popover; right-click shows the app menu.
    @objc func statusItemClicked(_ sender: AnyObject?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showMenu() {
        closePopover(nil)

        let menu = NSMenu()
        let about = NSMenuItem(title: "Acerca de \(Brand.appName)",
                               action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Abrir \(Brand.appName)",
                              action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let toggle = NSMenuItem(title: SpeechManager.shared.isRecording ? "Detener dictado" : "Iniciar dictado",
                                action: #selector(toggleRecordingFromMenu), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // popUpMenu is deprecated; assigning the menu and re-clicking is the supported path.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func showAbout() { AboutWindowController.shared.show() }
    @objc private func openFromMenu() { showPopover() }
    @objc private func toggleRecordingFromMenu() { SpeechManager.shared.toggleRecording() }

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
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: Brand.appName)
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
struct ConetxoListenerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        // Settings escena vacía para que no abra ventanas del Dock y corra 100% de fondo
        Settings {
            EmptyView()
        }
    }
}
