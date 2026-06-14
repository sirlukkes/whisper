#!/bin/bash
# Clone (pinned) and compile whisper.cpp to static libraries for Intel macOS (CPU + Accelerate).
# Idempotent: skips clone/checkout/build if already present.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/../vendor/whisper.cpp"
WHISPER_TAG="v1.8.6"
WHISPER_COMMIT="23ee03506a91ac3d3f0071b40e66a430eebdfa1d"

if [ ! -d "$VENDOR_DIR/.git" ]; then
  echo "📥 Cloning whisper.cpp $WHISPER_TAG ..."
  git clone https://github.com/ggerganov/whisper.cpp "$VENDOR_DIR"
fi

echo "📌 Pinning whisper.cpp to $WHISPER_TAG ($WHISPER_COMMIT)"
git -C "$VENDOR_DIR" fetch --tags --quiet
git -C "$VENDOR_DIR" checkout --quiet "$WHISPER_COMMIT"

BUILD_DIR="$VENDOR_DIR/build"
if [ ! -f "$BUILD_DIR/.built_ok" ]; then
  echo "⚙️  Configuring + building whisper.cpp static libs (this is slow the first time)..."
  cmake -B "$BUILD_DIR" -S "$VENDOR_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=OFF \
    -DGGML_ACCELERATE=ON \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF
  cmake --build "$BUILD_DIR" --config Release -j
  touch "$BUILD_DIR/.built_ok"
fi

echo "✅ whisper.cpp libs:"
find "$BUILD_DIR" -name "*.a" -print
