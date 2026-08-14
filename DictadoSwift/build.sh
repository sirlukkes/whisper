#!/bin/bash
set -e

# Nombre de la aplicación y directorios
APP_NAME="Conetxo Listener"
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
swiftc -o "$MACOS_DIR/ConetxoListener" \
    -sdk "$SDK_PATH" \
    -target "${ARCH}-apple-macosx13.0" \
    -O \
    -import-objc-header "$SCRIPT_DIR/whisper-bridging.h" \
    -I "$VENDOR/include" -I "$VENDOR/ggml/include" \
    -framework Accelerate -framework AVFoundation -lc++ \
    DictadoWhisperApp.swift \
    BrandKit.swift \
    ContentView.swift \
    SpeechManager.swift \
    HotkeyManager.swift \
    SettingsManager.swift \
    HistoryManager.swift \
    WhisperEngine.swift \
    CloudEngine.swift \
    AudioRecorder.swift \
    ModelManager.swift \
    $WLIBS

echo "📄 Copiando Info.plist..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Brand assets (app icon + UI logo) ship in the repo, versioned alongside the code.
echo "🎨 Copiando assets de marca..."
cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$SCRIPT_DIR/Resources/BrandLogo.png" "$RESOURCES_DIR/BrandLogo.png"
cp "$SCRIPT_DIR/Resources/BrandLogo@2x.png" "$RESOURCES_DIR/BrandLogo@2x.png"
cp "$SCRIPT_DIR/Resources/BrandLogo@3x.png" "$RESOURCES_DIR/BrandLogo@3x.png"

echo "🔏 Firmando la aplicación localmente (ad-hoc)..."
# Strip extended attributes (resource forks / Finder info / quarantine) from the bundle.
# Without this, codesign fails on stricter Macs with:
#   "resource fork, Finder information, or similar detritus not allowed"
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "🚀 Instalando la aplicación en /Applications..."
# The executable is "ConetxoListener" (no space); kill by that name + the display name.
# Legacy names stay in the list so an upgrade from Dictado Whisper does not leave a stray process.
killall ConetxoListener "Conetxo Listener" DictadoWhisper "Dictado Whisper" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_BUNDLE" "/Applications/"

echo "✅ ¡$APP_NAME.app compilada e instalada en /Applications con éxito!"
echo "Abriendo la aplicación desde /Applications..."
open "/Applications/$APP_NAME.app"
