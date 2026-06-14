import Speech
import AVFoundation
import Cocoa

class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()
    
    @Published var statusText: String = "Listo"
    @Published var isRecording: Bool = false {
        didSet {
            NotificationCenter.default.post(name: .recordingStateChanged, object: nil)
        }
    }
    @Published var currentTranscription: String = ""
    @Published var isAccessibilityAuthorized: Bool = false
    
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    
    private var isAuthorized = false
    
    // Guardar referencia a la app que tenía foco antes de grabar, para restaurarla al pegar
    private var previousApp: NSRunningApplication?
    private var lastActiveApp: NSRunningApplication?
    private var pythonProcess: Process?
    
    override init() {
        super.init()
        setupRecognizer()
        checkAccessibilityPermissions()
        
        // Escuchar el atajo de teclado global
        NotificationCenter.default.addObserver(self, selector: #selector(toggleRecording), name: .globalHotkeyTriggered, object: nil)
        
        // Observar cambios de aplicación activa para guardar cuál era la aplicación de edición real del usuario
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceDidActivateApplication(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        // Observar cambios de configuración de Whisper (para reiniciar o detener el proceso de Python)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSettingsChanged), name: .whisperSettingsChanged, object: nil)
        
        // Inicializar con la aplicación actualmente activa
        if let active = NSWorkspace.shared.frontmostApplication, active.bundleIdentifier != NSRunningApplication.current.bundleIdentifier {
            self.lastActiveApp = active
        }
        
        // Solicitar permisos al iniciar
        requestPermissions()
        
        // Si al iniciar el motor seleccionado es Python, lanzar la aplicación de Python de fondo
        if SettingsManager.shared.engine == "whisper_python" {
            launchPythonApp()
        }
    }
    
    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            if app.bundleIdentifier != NSRunningApplication.current.bundleIdentifier {
                self.lastActiveApp = app
                print("[Focus] Aplicación de trabajo guardada: \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? ""))")
            }
        }
    }
    
    @objc private func handleSettingsChanged() {
        DispatchQueue.main.async {
            if SettingsManager.shared.engine == "whisper_python" {
                // Reiniciar el proceso de Python para que cargue la nueva configuración (ej. cambio de modelo/idioma)
                self.restartPythonProcess()
            } else {
                // Si cambiaron a Apple Local, matamos el proceso de Python para liberar recursos de la GPU/CPU/RAM
                self.terminatePythonProcess()
            }
        }
    }
    
    func restartPythonProcess() {
        terminatePythonProcess()
        // Esperar un momento a que se libere el proceso anterior y luego lanzar de nuevo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if SettingsManager.shared.engine == "whisper_python" {
                self.launchPythonApp()
            }
        }
    }
    
    func terminatePythonProcess() {
        if let process = pythonProcess, process.isRunning {
            process.terminate()
            print("[Python] Proceso de Python terminado.")
        }
        pythonProcess = nil
    }
    
    func checkAccessibilityPermissions() {
        DispatchQueue.main.async {
            self.isAccessibilityAuthorized = AXIsProcessTrusted()
        }
    }
    
    func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async {
            self.isAccessibilityAuthorized = trusted
        }
    }
    
    func setupRecognizer() {
        let langCode = SettingsManager.shared.language
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: langCode))
        print("SpeechRecognizer inicializado para idioma: \(langCode)")
    }
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self.isAuthorized = true
                    self.statusText = "Listo"
                case .denied, .restricted, .notDetermined:
                    self.isAuthorized = false
                    self.statusText = "⚠️ Sin permisos de reconocimiento de voz"
                @unknown default:
                    break
                }
            }
        }
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.statusText = "⚠️ Sin permisos de micrófono"
                }
            }
        }
    }
    
    @objc func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Guardar la app activa ANTES de cualquier acción para poder restaurar el foco después
        if let lastApp = self.lastActiveApp {
            self.previousApp = lastApp
        } else if let currentFront = NSWorkspace.shared.frontmostApplication, currentFront.bundleIdentifier != NSRunningApplication.current.bundleIdentifier {
            self.previousApp = currentFront
        } else {
            self.previousApp = nil
        }
        print("[Focus] startRecording - previousApp fijada como: \(self.previousApp?.localizedName ?? "ninguna")")
        
        // Si el motor seleccionado es Python, lanzar la aplicación de Python original
        if SettingsManager.shared.engine == "whisper_python" {
            launchPythonApp()
            return
        }
        
        // Actualizar el reconocedor si cambió el idioma
        setupRecognizer()
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            updateStatus("❌ Motor de voz no disponible", play: "Basso")
            return
        }
        
        // Detener cualquier tarea anterior
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        // Forzar reconocimiento local (offline, privado, sin servidor Apple)
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Limpiar taps previos por seguridad
        inputNode.removeTap(onBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
            currentTranscription = ""
            updateStatus("🎤 Grabando...", play: "Tink")
            
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                var isFinal = false
                
                if let result = result {
                    DispatchQueue.main.async {
                        self.currentTranscription = result.bestTranscription.formattedString
                    }
                    isFinal = result.isFinal
                }
                
                if error != nil || isFinal {
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    
                    if let error = error {
                        print("Error en reconocimiento: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            updateStatus("❌ Error al iniciar audio", play: "Basso")
            print("Error al iniciar motor de audio: \(error)")
        }
    }
    
    private func getPythonPath() -> String {
        let paths = [
            "/opt/homebrew/bin/python3.12",
            "/usr/local/bin/python3.12",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        let fileManager = FileManager.default
        for path in paths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return "/usr/bin/env"
    }

    private func launchPythonApp() {
        // Si ya hay un proceso de Python corriendo, no lo volvemos a lanzar
        if let process = pythonProcess, process.isRunning {
            print("[Python] El proceso de Python ya está en ejecución.")
            return
        }
        
        // Limpieza de referencias muertas
        if pythonProcess != nil {
            pythonProcess = nil
        }
        
        updateStatus("Lanzando Whisper Python...", play: "Tink")
        
        let pythonPath = getPythonPath()
        let task = Process()
        self.pythonProcess = task
        
        // Inyectar rutas comunes al PATH para que el subproceso de Python pueda localizar ffmpeg, etc.
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + currentPath
        // CRÍTICO: Forzar stdout sin buffer para que los mensajes [LOG] lleguen en tiempo real
        env["PYTHONUNBUFFERED"] = "1"
        task.environment = env
        
        if pythonPath == "/usr/bin/env" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["python3", "-u", "/Users/lukkes/Developer/whisper/dictado_whisper.py", "--headless"]
        } else {
            task.executableURL = URL(fileURLWithPath: pythonPath)
            task.arguments = ["-u", "/Users/lukkes/Developer/whisper/dictado_whisper.py", "--headless"]
        }
        
        // Capturar stdout para leer los mensajes [LOG] y mostrar progreso de descarga en la UI de Swift
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let outputString = String(data: data, encoding: .utf8) else { return }
            // Buscar líneas [LOG] del script de Python y extraer el mensaje
            for line in outputString.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("[LOG] ") {
                    let logMessage = String(trimmed.dropFirst(6))
                    DispatchQueue.main.async {
                        self.statusText = "🐍 " + logMessage
                    }
                }
            }
        }
        
        // Capturar stderr para depuración y mostrar errores en la UI
        let errorPipe = Pipe()
        task.standardError = errorPipe
        let errorHandle = errorPipe.fileHandleForReading
        var stderrAccumulator = ""
        let stderrLock = NSLock()
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let errorString = String(data: data, encoding: .utf8), !errorString.isEmpty {
                print("[Python Error] \(errorString)")
                stderrLock.lock()
                stderrAccumulator += errorString
                stderrLock.unlock()
            }
        }
        
        // Cuando el proceso termine, actualizar el estado y limpiar los handlers
        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                
                if self?.pythonProcess == process {
                    self?.pythonProcess = nil
                }
                
                let exitCode = process.terminationStatus
                if exitCode == 0 {
                    self?.statusText = "Listo"
                } else {
                    // Si el proceso terminó intencionadamente por un SIGTERM (código 15), no mostrar error
                    if exitCode == 15 {
                        self?.statusText = "Listo"
                        return
                    }
                    
                    // Extraer la última línea significativa de stderr como mensaje de error
                    stderrLock.lock()
                    let errorLines = stderrAccumulator
                    stderrLock.unlock()
                    
                    let lastLine = errorLines
                        .components(separatedBy: .newlines)
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        .last ?? "Error desconocido"
                    
                    self?.statusText = "❌ Python: \(String(lastLine.prefix(80)))"
                    
                    // Regresar a Listo después de 8 segundos para dar tiempo a leer el error
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                        if !(self?.isRecording ?? false) {
                            self?.statusText = "Listo"
                        }
                    }
                }
            }
        }
        
        do {
            try task.run()
        } catch {
            print("Error lanzando la app en Python: \(error)")
            updateStatus("❌ Error al lanzar Python", play: "Basso")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        updateStatus("⌛ Transcribiendo...", play: "Ping")
        
        // Cerrar el popover si está abierto
        DispatchQueue.main.async {
            if let delegate = NSApplication.shared.delegate as? AppDelegate {
                delegate.closePopover(nil)
            }
        }
        
        audioEngine.stop()
        recognitionRequest?.endAudio()
        
        // Esperar un momento para recibir el resultado final antes de procesar
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let text = self.currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                self.updateStatus("✍️ Transcrito: \"\(text.prefix(30))...\"", play: "Glass")
                self.copyAndPasteText(text)
                HistoryManager.shared.addEntry(text: text)
            } else {
                self.updateStatus("⚠️ No se detectó voz", play: "Pop")
            }
            
            // Regresar a Listo después de 3 segundos
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if !self.isRecording {
                    self.statusText = "Listo"
                }
            }
        }
    }
    
    private func updateStatus(_ text: String, play soundName: String? = nil) {
        DispatchQueue.main.async {
            self.statusText = text
            if let sound = soundName {
                self.playGuideSound(sound)
            }
        }
    }
    
    private func playGuideSound(_ name: String) {
        guard SettingsManager.shared.playSounds else { return }
        let path = "/System/Library/Sounds/\(name).aiff"
        let url = URL(fileURLWithPath: path)
        var soundID: SystemSoundID = 0
        AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        AudioServicesPlaySystemSound(soundID)
    }
    
    private func copyAndPasteText(_ text: String) {
        // 1. Copiar al portapapeles
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        print("[Paste] Texto copiado al portapapeles: \"\(text.prefix(40))...\"")
        print("[Paste] App anterior guardada: \(self.previousApp?.localizedName ?? "ninguna")")
        print("[Paste] AXIsProcessTrusted: \(AXIsProcessTrusted())")
        
        // 2. Restaurar el foco a la app que lo tenía ANTES de grabar
        if let prevApp = self.previousApp {
            prevApp.activate(options: [.activateIgnoringOtherApps])
            print("[Paste] Activando app anterior: \(prevApp.localizedName ?? "?")")
        }
        
        // 3. Simular Cmd+V usando un enfoque condicional
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if AXIsProcessTrusted() {
                // Si la app está autorizada en accesibilidad, usar CGEvent que es nativo e instantáneo
                let source = CGEventSource(stateID: .combinedSessionState)
                let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
                vDown?.flags = .maskCommand
                let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                vUp?.flags = .maskCommand
                
                vDown?.post(tap: .cghidEventTap)
                vUp?.post(tap: .cghidEventTap)
                print("[Paste] CGEvent Cmd+V enviado (Proceso de Confianza)")
            } else {
                // Si no, intentar con AppleScript como fallback alternativo
                let script = NSAppleScript(source: """
                    tell application "System Events"
                        keystroke "v" using command down
                    end tell
                """)
                var errorDict: NSDictionary?
                script?.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    print("[Paste] AppleScript fallback falló: \(error)")
                } else {
                    print("[Paste] AppleScript fallback ejecutado con éxito")
                }
            }
        }
        
        // Actualizar el estado del permiso en segundo plano
        self.checkAccessibilityPermissions()
    }
}

extension Notification.Name {
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
}
