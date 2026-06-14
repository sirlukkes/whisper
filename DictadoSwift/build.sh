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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧱 Building whisper.cpp static libs..."
"$SCRIPT_DIR/scripts/build_whisper_lib.sh"
VENDOR="$SCRIPT_DIR/vendor/whisper.cpp"
WLIBS=$(find "$VENDOR/build" -name "*.a")

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
    -import-objc-header "$SCRIPT_DIR/whisper-bridging.h" \
    -I "$VENDOR/include" -I "$VENDOR/ggml/include" \
    -framework Accelerate -framework AVFoundation -lc++ \
    DictadoWhisperApp.swift \
    ContentView.swift \
    SpeechManager.swift \
    HotkeyManager.swift \
    SettingsManager.swift \
    HistoryManager.swift \
    WhisperEngine.swift \
    AudioRecorder.swift \
    ModelManager.swift \
    $WLIBS

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
# Strip extended attributes (resource forks / Finder info / quarantine) from the bundle.
# Without this, codesign fails on stricter Macs with:
#   "resource fork, Finder information, or similar detritus not allowed"
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "🚀 Instalando la aplicación en /Applications..."
# The executable is "DictadoWhisper" (no space); kill by that name + the display name to be safe.
killall DictadoWhisper "Dictado Whisper" 2>/dev/null || true
rm -rf "/Applications/Dictado Whisper.app"
cp -R "$APP_BUNDLE" "/Applications/"

echo "✅ ¡$APP_NAME.app compilada e instalada en /Applications con éxito!"
echo "Abriendo la aplicación desde /Applications..."
open "/Applications/Dictado Whisper.app"
