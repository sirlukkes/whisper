#!/bin/bash
# Compile and run the Swift test binaries against the vendored whisper.cpp libs.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DS_DIR="$SCRIPT_DIR/.."
VENDOR="$DS_DIR/vendor/whisper.cpp"
SDK="$(xcrun --show-sdk-path)"
ARCH="x86_64"; [ "$(uname -m)" = "arm64" ] && ARCH="arm64"
TARGET="${ARCH}-apple-macosx13.0"
OUT="$SCRIPT_DIR/_bin"; mkdir -p "$OUT"

# Ensure libs are built
"$DS_DIR/scripts/build_whisper_lib.sh" >/dev/null

WLIBS=$(find "$VENDOR/build" -name "*.a")
INCS=(-I "$VENDOR/include" -I "$VENDOR/ggml/include")
COMMON=(-sdk "$SDK" -target "$TARGET" -O -framework Accelerate -framework AVFoundation -lc++)

# Ensure base model present for the engine test
MODEL="$VENDOR/models/ggml-base.bin"
if [ ! -f "$MODEL" ]; then
  echo "📥 Downloading base model for tests..."
  bash "$VENDOR/models/download-ggml-model.sh" base "$VENDOR/models" >/dev/null 2>&1 || \
  bash "$VENDOR/models/download-ggml-model.sh" base >/dev/null 2>&1
fi

FAILED=0

run_test() {
  local name="$1"; shift
  echo "🔨 Building $name ..."
  if swiftc "${COMMON[@]}" "${INCS[@]}" -import-objc-header "$DS_DIR/whisper-bridging.h" \
       "$@" $WLIBS -o "$OUT/$name"; then
    echo "▶️  Running $name ..."
    "$OUT/$name" "${TEST_ARGS[@]}" || FAILED=1
  else
    echo "❌ build failed: $name"; FAILED=1
  fi
}

# test_engine needs model + wav as args
TEST_ARGS=("$MODEL" "$VENDOR/samples/jfk.wav")
run_test test_engine "$DS_DIR/WhisperEngine.swift" "$SCRIPT_DIR/test_engine.swift"

exit $FAILED
