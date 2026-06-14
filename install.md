# Dictado Whisper — Instalación (app nativa)

App de dictado por voz para macOS. Motor por defecto: **Whisper nativo** (whisper.cpp, multidioma con auto-detección). Motor alterno: **Apple** (dictado local del sistema).

## Requisitos
- macOS 13+ (Intel o Apple Silicon).
- Command Line Tools (`xcode-select --install`) y `cmake` (`brew install cmake`).

## Compilar e instalar
```bash
cd DictadoSwift
./build.sh
```
La primera compilación clona y compila whisper.cpp (~1–2 min). Las siguientes son rápidas. La app se instala en `/Applications` y arranca en la barra de menús.

## Primer uso
1. **Micrófono**: acepta el permiso al primer dictado.
2. **Accesibilidad** (para pegar con Cmd+V): Configuración del Sistema → Privacidad y Seguridad → Accesibilidad → activa "Dictado Whisper".
3. **Modelo Whisper**: abre el panel (ícono de micrófono), elige el modelo (por defecto `base`, ~142 MB). Se descarga mostrando una barra de progreso. Una vez descargado, funciona 100% offline.

## Uso
- Coloca el cursor donde quieras escribir.
- Pulsa el atajo global (por defecto ⌃⌥R) para empezar/parar. El texto se transcribe y se pega solo.
