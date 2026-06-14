#!/bin/bash
set -e

# Nombre de la aplicación y directorios
APP_NAME="Dictado Whisper"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "🧹 Limpiando compilaciones anteriores..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "⚙️ Compilando archivos Swift..."
# Obtener SDK de macOS
SDK_PATH=$(xcrun --show-sdk-path)

# Compilar todos los archivos Swift en el binario final
ARCH="x86_64"
if [ "$(uname -m)" = "arm64" ]; then
    ARCH="arm64"
fi

echo "Compilando para arquitectura $ARCH..."
swiftc -o "$MACOS_DIR/DictadoWhisper" \
    -sdk "$SDK_PATH" \
    -target "${ARCH}-apple-macosx13.0" \
    -O \
    DictadoWhisperApp.swift \
    ContentView.swift \
    SpeechManager.swift \
    HotkeyManager.swift \
    SettingsManager.swift \
    HistoryManager.swift

echo "📄 Copiando Info.plist..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Intentar buscar e importar el ícono de la app anterior para no perder el diseño de IA
ICON_PATH=""
if [ -f "/Applications/Dictado Whisper.app/Contents/Resources/AppIcon.icns" ]; then
    ICON_PATH="/Applications/Dictado Whisper.app/Contents/Resources/AppIcon.icns"
elif [ -f "../Dictado Whisper.app/Contents/Resources/AppIcon.icns" ]; then
    ICON_PATH="../Dictado Whisper.app/Contents/Resources/AppIcon.icns"
fi

if [ -n "$ICON_PATH" ]; then
    echo "🎨 Copiando ícono existente desde: $ICON_PATH"
    cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
else
    echo "⚠️ No se encontró el archivo AppIcon.icns. La app usará el ícono genérico."
fi

echo "🔏 Firmando la aplicación localmente (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "🚀 Instalando la aplicación en /Applications..."
killall "Dictado Whisper" 2>/dev/null || true
rm -rf "/Applications/Dictado Whisper.app"
cp -R "$APP_BUNDLE" "/Applications/"

echo "✅ ¡$APP_NAME.app compilada e instalada en /Applications con éxito!"
echo "Abriendo la aplicación desde /Applications..."
open "/Applications/Dictado Whisper.app"
