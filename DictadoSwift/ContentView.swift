import SwiftUI
import Carbon

struct ContentView: View {
    @ObservedObject var speechManager: SpeechManager
    @StateObject private var settings = SettingsManager.shared
    @ObservedObject private var historyManager = HistoryManager.shared
    @ObservedObject private var models = ModelManager.shared
    
    // Pestaña activa (0 = Dictar, 1 = Historial)
    @State private var activeTab = 0
    
    // Búsqueda en el historial
    @State private var searchText = ""
    
    // Estado para grabación de atajo
    @State private var isListeningForShortcut = false
    @State private var keyMonitor: Any? = nil
    
    // Detectar el esquema de colores del sistema para el modo automático
    @Environment(\.colorScheme) var systemColorScheme
    
    // Opciones de idioma disponibles
    let languages = [
        ("Español (España)", "es-ES"),
        ("Español (México)", "es-MX"),
        ("Inglés (EEUU)", "en-US"),
        ("Inglés (Reino Unido)", "en-GB"),
        ("Francés", "fr-FR"),
        ("Alemán", "de-DE"),
        ("Italiano", "it-IT"),
        ("Portugués (Brasil)", "pt-BR")
    ]
    
    // Estado para animar el botón de grabación
    @State private var pulseScale: CGFloat = 1.0
    
    // Resolver si debemos mostrar el modo oscuro o claro
    var isDark: Bool {
        if settings.theme == "system" {
            return systemColorScheme == .dark
        } else {
            return settings.theme == "dark"
        }
    }
    
    // Atajos semánticos de color resueltos dinámicamente
    var baseColor: Color { Color.themeBase(isDark: isDark) }
    var cardColor: Color { Color.themeCard(isDark: isDark) }
    var crustColor: Color { Color.themeCrust(isDark: isDark) }
    var surfaceColor: Color { Color.themeSurface(isDark: isDark) }
    var lavenderColor: Color { Color.themeLavender(isDark: isDark) }
    var greenColor: Color { Color.themeGreen(isDark: isDark) }
    var redColor: Color { Color.themeRed(isDark: isDark) }
    var yellowColor: Color { Color.themeYellow(isDark: isDark) }
    var textColor: Color { Color.themeText(isDark: isDark) }
    var subtextColor: Color { Color.themeSubtext(isDark: isDark) }
    
    var body: some View {
        VStack(spacing: 0) {
            // Selector superior de Pestañas (Dictar vs Historial)
            HStack(spacing: 0) {
                tabButton(title: "🎙️ Dictar", index: 0)
                tabButton(title: "📜 Historial", index: 1)
            }
            .background(cardColor)
            .overlay(
                Rectangle()
                    .fill(surfaceColor.opacity(0.3))
                    .frame(height: 1),
                alignment: .bottom
            )
            
            // Contenedor principal de vistas
            VStack {
                if activeTab == 0 {
                    dictationTab
                } else {
                    historyTab
                }
            }
            .padding(14)
        }
        .frame(width: 380, height: 450) // Ancho y alto ampliados para mejor legibilidad
        .background(baseColor)
        .preferredColorScheme(settings.theme == "system" ? nil : (settings.theme == "dark" ? .dark : .light))
        .onAppear {
            speechManager.checkAccessibilityPermissions()
            if settings.engine == "whisper" { models.ensureDownloaded(settings.whisperModel) }
        }
        .onDisappear {
            stopShortcutListening()
        }
    }
    
    // Pestaña 1: Dictar y Configurar
    private var dictationTab: some View {
        VStack(spacing: 12) {
            // Cabecera y botón de grabación
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dictado Nativo")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(lavenderColor)
                    
                    Text(speechManager.statusText)
                        .font(.system(size: 14))
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Botón con pulso animado
                ZStack {
                    if speechManager.isRecording {
                        Circle()
                            .stroke(redColor.opacity(0.4), lineWidth: 4)
                            .scaleEffect(pulseScale)
                            .opacity(Double(2.0 - pulseScale))
                            .onAppear {
                                withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                                    self.pulseScale = 2.0
                                }
                            }
                            .onDisappear {
                                self.pulseScale = 1.0
                            }
                    }
                    
                    Button(action: {
                        speechManager.toggleRecording()
                    }) {
                        Image(systemName: speechManager.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(baseColor)
                            .frame(width: 38, height: 38)
                            .background(speechManager.isRecording ? redColor : lavenderColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(width: 42, height: 42)
            }
            
            // Vista previa de la transcripción en tiempo real
            if speechManager.isRecording || !speechManager.currentTranscription.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Texto detectado:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(subtextColor)
                    
                    ScrollView {
                        Text(speechManager.currentTranscription.isEmpty ? "Escuchando..." : speechManager.currentTranscription)
                            .font(.system(size: 14))
                            .foregroundColor(speechManager.currentTranscription.isEmpty ? subtextColor.opacity(0.6) : textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 60)
                    .padding(6)
                    .background(crustColor.opacity(0.5))
                    .cornerRadius(6)
                }
            } else {
                Spacer()
                    .frame(height: 60)
            }
            
            // Tarjeta de Ajustes
            ScrollView {
                VStack(spacing: 8) {
                    // 1. Selector de Idioma (solo para Apple; Whisper detecta idioma automáticamente)
                    if settings.engine == "apple" {
                        HStack {
                            Text("Idioma:")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(textColor)
                            Spacer()
                            Picker("", selection: $settings.language) {
                                ForEach(languages, id: \.1) { name, code in
                                    Text(name).tag(code)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 195)
                            .labelsHidden()
                        }

                        Divider()
                            .background(surfaceColor.opacity(0.3))
                    }

                    // 2. Selector de Motor/Motor
                    HStack {
                        Text("Motor:")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(textColor)
                        Spacer()
                        Picker("", selection: $settings.engine) {
                            Text("Whisper Local").tag("whisper")
                            Text("Apple Local").tag("apple")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 195)
                        .labelsHidden()
                    }
                    
                    // 2b. Selector de Modelo Whisper (Solo si el motor es whisper)
                    if settings.engine == "whisper" {
                        Divider().background(surfaceColor.opacity(0.3))
                        HStack {
                            Text("Modelo:").font(.system(size: 14, weight: .bold)).foregroundColor(textColor)
                            Spacer()
                            Picker("", selection: $settings.whisperModel) {
                                ForEach(ModelManager.catalog) { m in Text(m.displayName).tag(m.id) }
                            }
                            .pickerStyle(MenuPickerStyle()).frame(width: 195).labelsHidden()
                            .onChange(of: settings.whisperModel) { newId in models.ensureDownloaded(newId) }
                        }
                        whisperModelStatusRow
                    }
                    
                    Divider()
                        .background(surfaceColor.opacity(0.3))
                    
                    // 3. Grabador de Atajo de Teclado
                    HStack {
                        Text("Atajo Global:")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(textColor)
                        Spacer()
                        
                        Button(action: {
                            if isListeningForShortcut {
                                stopShortcutListening()
                            } else {
                                startShortcutListening()
                            }
                        }) {
                            Text(isListeningForShortcut ? "Pulsa teclas..." : settings.hotkeyDescription)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundColor(isListeningForShortcut ? baseColor : lavenderColor)
                                .background(isListeningForShortcut ? greenColor : surfaceColor)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isListeningForShortcut ? greenColor : lavenderColor.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Divider()
                        .background(surfaceColor.opacity(0.3))
                    
                    // 4. Selector de Tema UI (Claro/Oscuro/Sistema)
                    HStack {
                        Text("Tema UI:")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(textColor)
                        Spacer()
                        Picker("", selection: $settings.theme) {
                            Text("Automático").tag("system")
                            Text("Claro").tag("light")
                            Text("Oscuro").tag("dark")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 195)
                        .labelsHidden()
                    }
                    
                    Divider()
                        .background(surfaceColor.opacity(0.3))
                    
                    // 4b. Permiso de Accesibilidad (Pegado automático)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Pegado automático:")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(textColor)
                            Spacer()
                            
                            Button(action: {
                                speechManager.requestAccessibilityPermissions()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: speechManager.isAccessibilityAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    Text(speechManager.isAccessibilityAuthorized ? "Habilitado" : "Activar")
                                }
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundColor(baseColor)
                                .background(speechManager.isAccessibilityAuthorized ? greenColor : lavenderColor)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Text("⚠️ Si ya lo activaste pero no pega, apaga y vuelve a encender 'Dictado Whisper' en Configuración del Sistema > Privacidad y Seguridad > Accesibilidad.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(yellowColor)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    
                    Divider()
                        .background(surfaceColor.opacity(0.3))
                    
                    // 5. Opción de Sonido
                    Toggle(isOn: $settings.playSounds) {
                        Text("Sonidos guía")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(textColor)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: lavenderColor))
                }
                .padding(10)
                .background(cardColor)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(surfaceColor.opacity(0.5), lineWidth: 1)
                )
            }
            .frame(maxHeight: 230)
            
            Spacer()
            
            // Información inferior y botón de salir
            HStack(alignment: .center, spacing: 10) {
                Text(isListeningForShortcut ? "Presiona Esc para cancelar." : "Atajo de voz para empezar/parar la grabación.")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(subtextColor.opacity(0.8))
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text("Salir")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(redColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(surfaceColor.opacity(0.3))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // Pestaña 2: Historial
    private var historyTab: some View {
        VStack(spacing: 10) {
            // Buscador del Historial
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(subtextColor)
                
                TextField("Buscar en historial...", text: $searchText)
                    .font(.system(size: 14))
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(surfaceColor.opacity(0.4))
            .cornerRadius(6)
            
            // Lista con Scroll
            ScrollView {
                VStack(spacing: 8) {
                    if filteredHistory.isEmpty {
                        Text(searchText.isEmpty ? "No hay registros grabados" : "No se encontraron coincidencias")
                            .font(.system(size: 14))
                            .foregroundColor(subtextColor.opacity(0.6))
                            .padding(.top, 40)
                    } else {
                        ForEach(filteredHistory) { entry in
                            HistoryRow(entry: entry, isDark: isDark)
                        }
                    }
                }
            }
            
            // Botones inferiores de exportación
            HStack(spacing: 12) {
                Button(action: {
                    HistoryManager.shared.openMarkdownFile()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.fill")
                        Text("Ver archivo MD")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(baseColor)
                    .background(lavenderColor)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    HistoryManager.shared.clearHistory()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Borrar")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.vertical, 8)
                    .frame(maxWidth: 70)
                    .foregroundColor(redColor)
                    .background(surfaceColor)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(redColor.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 4)
        }
    }
    
    // Filtrado de historial basado en búsqueda
    private var filteredHistory: [HistoryEntry] {
        if searchText.isEmpty {
            return historyManager.entries
        } else {
            return historyManager.entries.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    // Ayudante de botones de pestañas
    private func tabButton(title: String, index: Int) -> some View {
        Button(action: { activeTab = index }) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(activeTab == index ? lavenderColor : subtextColor)
                    .padding(.top, 8)
                Rectangle()
                    .fill(activeTab == index ? lavenderColor : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
    }
    
    // Color de estado
    private var statusColor: Color {
        if speechManager.statusText.contains("🎤") {
            return greenColor
        } else if speechManager.statusText.contains("❌") || speechManager.statusText.contains("⚠️") {
            return redColor
        } else if speechManager.statusText.contains("⌛") {
            return yellowColor
        } else {
            return subtextColor
        }
    }
    
    // Model download status row for the Whisper engine section
    @ViewBuilder private var whisperModelStatusRow: some View {
        let state = models.states[settings.whisperModel] ?? (models.isReady(settings.whisperModel) ? .ready : .notDownloaded)
        switch state {
        case .ready:
            Label("Modelo listo", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundColor(greenColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .downloading(let fraction, let detail):
            VStack(alignment: .leading, spacing: 3) {
                Text("Descargando modelo… \(detail)").font(.system(size: 11)).foregroundColor(yellowColor)
                ProgressView(value: fraction).tint(lavenderColor)
            }
        case .notDownloaded:
            Button("Descargar modelo") { models.ensureDownloaded(settings.whisperModel) }
                .font(.system(size: 11, weight: .bold)).foregroundColor(lavenderColor)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 3) {
                Text("❌ \(msg)").font(.system(size: 11)).foregroundColor(redColor)
                Button("Reintentar") { models.ensureDownloaded(settings.whisperModel) }
                    .font(.system(size: 11, weight: .bold)).foregroundColor(lavenderColor)
            }
        }
    }

    // Funciones del monitor de atajo dinámico
    private func startShortcutListening() {
        isListeningForShortcut = true
        
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode)
            
            // Si pulsan Escape solo, cancelamos la grabación
            let modifiersOnly = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if keyCode == 53 && modifiersOnly.isEmpty {
                self.stopShortcutListening()
                return nil
            }
            
            var modifiers = 0
            if event.modifierFlags.contains(.control) { modifiers |= 4096 }
            if event.modifierFlags.contains(.option) { modifiers |= 2048 }
            if event.modifierFlags.contains(.shift) { modifiers |= 512 }
            if event.modifierFlags.contains(.command) { modifiers |= 256 }
            
            // Actualizar atajo
            SettingsManager.shared.hotkeyCode = keyCode
            SettingsManager.shared.hotkeyModifiers = modifiers
            
            self.stopShortcutListening()
            return nil
        }
    }
    
    private func stopShortcutListening() {
        isListeningForShortcut = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

// Fila del historial con botón de copiado individual y feedback
struct HistoryRow: View {
    let entry: HistoryEntry
    let isDark: Bool
    
    @State private var copied = false
    
    var cardColor: Color { Color.themeCard(isDark: isDark) }
    var textColor: Color { Color.themeText(isDark: isDark) }
    var subtextColor: Color { Color.themeSubtext(isDark: isDark) }
    var surfaceColor: Color { Color.themeSurface(isDark: isDark) }
    var greenColor: Color { Color.themeGreen(isDark: isDark) }
    var lavenderColor: Color { Color.themeLavender(isDark: isDark) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(.system(size: 14))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
            
            HStack {
                Text(formatDate(entry.date))
                    .font(.system(size: 11))
                    .foregroundColor(subtextColor.opacity(0.6))
                
                Spacer()
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Copiado" : "Copiar")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(copied ? greenColor : lavenderColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(surfaceColor.opacity(0.4))
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(8)
        .background(cardColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(surfaceColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter.string(from: date)
    }
}

// Extensiones de Color para Paleta Catppuccin Mocha (Oscuro) y Latte (Claro) nativas sin Assets
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 1)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    // Métodos para resolver color dinámico basado en el modo del tema
    static func themeBase(isDark: Bool) -> Color {
        isDark ? Color(hex: "1e1e2e") : Color(hex: "eff1f5")
    }
    
    static func themeCard(isDark: Bool) -> Color {
        isDark ? Color(hex: "181825") : Color(hex: "e6e9ef")
    }
    
    static func themeCrust(isDark: Bool) -> Color {
        isDark ? Color(hex: "11111b") : Color(hex: "dce0e8")
    }
    
    static func themeSurface(isDark: Bool) -> Color {
        isDark ? Color(hex: "313244") : Color(hex: "ccd0da")
    }
    
    static func themeLavender(isDark: Bool) -> Color {
        isDark ? Color(hex: "cba6f7") : Color(hex: "5733FF")
    }
    
    static func themeGreen(isDark: Bool) -> Color {
        isDark ? Color(hex: "a6e3a1") : Color(hex: "40a02b")
    }
    
    static func themeRed(isDark: Bool) -> Color {
        isDark ? Color(hex: "f38ba8") : Color(hex: "d20f39")
    }
    
    static func themeYellow(isDark: Bool) -> Color {
        isDark ? Color(hex: "f9e2af") : Color(hex: "df8e1d")
    }
    
    static func themeText(isDark: Bool) -> Color {
        isDark ? Color(hex: "cdd6f4") : Color(hex: "4c4f69")
    }
    
    static func themeSubtext(isDark: Bool) -> Color {
        isDark ? Color(hex: "a6adc8") : Color(hex: "6c6f85")
    }
}
