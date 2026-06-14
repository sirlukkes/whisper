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

    // Whisper (in-process) engine
    private let audioRecorder = AudioRecorder()
    private var whisperEngine: WhisperEngine?
    private var loadedModelId: String?
    // Serial queue: serializes transcriptions and removes the data race on
    // whisperEngine/loadedModelId (also avoids two transcriptions fighting for CPU).
    private let whisperQueue = DispatchQueue(label: "com.lukkes.dictadowhisper.transcribe")

    // Guard so the Apple transcription finishes exactly once per round (isFinal or 3s safety net)
    private var finishedThisRound = false
    
    override init() {
        super.init()
        setupRecognizer()
        checkAccessibilityPermissions()
        
        // Escuchar el atajo de teclado global
        NotificationCenter.default.addObserver(self, selector: #selector(toggleRecording), name: .globalHotkeyTriggered, object: nil)
        
        // Observar cambios de aplicación activa para guardar cuál era la aplicación de edición real del usuario
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceDidActivateApplication(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        // Observar cambios de configuración (ej. cambio de idioma para el reconocedor de Apple)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSettingsChanged), name: .whisperSettingsChanged, object: nil)

        // Inicializar con la aplicación actualmente activa
        if let active = NSWorkspace.shared.frontmostApplication, active.bundleIdentifier != NSRunningApplication.current.bundleIdentifier {
            self.lastActiveApp = active
        }

        // Solicitar permisos al iniciar
        requestPermissions()
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
        // The Whisper engine reloads its model lazily on stop when the model id changes,
        // and the Apple flow re-creates the recognizer at the start of each recording,
        // so there is nothing to do here on a live settings change.
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
        capturePreviousApp()

        if SettingsManager.shared.engine == "whisper" {
            startWhisperRecording()
            return
        }
        startAppleRecording()
    }

    /// Save the app that had focus BEFORE recording so we can restore it when pasting.
    private func capturePreviousApp() {
        if let lastApp = self.lastActiveApp {
            self.previousApp = lastApp
        } else if let currentFront = NSWorkspace.shared.frontmostApplication, currentFront.bundleIdentifier != NSRunningApplication.current.bundleIdentifier {
            self.previousApp = currentFront
        } else {
            self.previousApp = nil
        }
        print("[Focus] startRecording - previousApp fijada como: \(self.previousApp?.localizedName ?? "ninguna")")
    }

    // MARK: - Whisper (in-process) engine

    private func startWhisperRecording() {
        let modelId = SettingsManager.shared.whisperModel
        guard ModelManager.shared.isReady(modelId) else {
            updateStatus("⬇️ Descarga el modelo primero (ajustes)", play: "Basso")
            ModelManager.shared.ensureDownloaded(modelId)
            return
        }
        do {
            try audioRecorder.start()
            isRecording = true
            currentTranscription = ""
            updateStatus("🎤 Grabando...", play: "Tink")
        } catch {
            updateStatus("❌ Error de micrófono", play: "Basso")
        }
    }

    private func stopWhisperRecording() {
        isRecording = false
        updateStatus("⌛ Transcribiendo...", play: "Ping")
        let samples = audioRecorder.stop()
        DispatchQueue.main.async {
            if let d = NSApplication.shared.delegate as? AppDelegate { d.closePopover(nil) }
        }
        whisperQueue.async { [weak self] in
            guard let self else { return }
            let modelId = SettingsManager.shared.whisperModel
            if self.whisperEngine == nil || self.loadedModelId != modelId {
                self.whisperEngine = WhisperEngine(modelPath: ModelManager.shared.localPath(for: modelId).path)
                self.loadedModelId = modelId
            }
            let text = self.whisperEngine?.transcribe(samples: samples, language: "auto")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                if text.isEmpty {
                    self.updateStatus("⚠️ No se detectó voz", play: "Pop")
                } else {
                    self.currentTranscription = text
                    self.updateStatus("✍️ Transcrito: \"\(text.prefix(30))...\"", play: "Glass")
                    self.copyAndPasteText(text)
                    HistoryManager.shared.addEntry(text: text)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if !self.isRecording { self.statusText = "Listo" }
                }
            }
        }
    }

    // MARK: - Apple (SFSpeechRecognizer) engine

    private func startAppleRecording() {
        finishedThisRound = false

        // Actualizar el reconocedor si cambió el idioma
        setupRecognizer()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            updateStatus("❌ Motor de voz no disponible", play: "Basso")
            return
        }
        // El dictado de Apple solo es privado/offline si el idioma soporta reconocimiento local.
        if !recognizer.supportsOnDeviceRecognition {
            updateStatus("⚠️ Este idioma no soporta dictado local de Apple. Usa Whisper.", play: "Basso")
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

                if let error = error {
                    print("Error en reconocimiento: \(error.localizedDescription)")
                }

                if error != nil || isFinal {
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    if isFinal { DispatchQueue.main.async { self.finishAppleTranscription() } }
                }
            }
        } catch {
            updateStatus("❌ Error al iniciar audio", play: "Basso")
            print("Error al iniciar motor de audio: \(error)")
        }
    }

    private func stopAppleRecording() {
        guard isRecording else { return }
        isRecording = false
        updateStatus("⌛ Transcribiendo...", play: "Ping")
        DispatchQueue.main.async {
            if let d = NSApplication.shared.delegate as? AppDelegate { d.closePopover(nil) }
        }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        // Safety net: if isFinal never arrives within 3s, finish with whatever we have.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, !self.finishedThisRound else { return }
            self.finishAppleTranscription()
        }
    }

    private func finishAppleTranscription() {
        guard !finishedThisRound else { return }
        finishedThisRound = true
        let text = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            updateStatus("✍️ Transcrito: \"\(text.prefix(30))...\"", play: "Glass")
            copyAndPasteText(text)
            HistoryManager.shared.addEntry(text: text)
        } else {
            updateStatus("⚠️ No se detectó voz", play: "Pop")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if !self.isRecording { self.statusText = "Listo" }
        }
    }

    // MARK: - Stop routing

    func stopRecording() {
        guard isRecording else { return }
        if SettingsManager.shared.engine == "whisper" { stopWhisperRecording(); return }
        stopAppleRecording()
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
