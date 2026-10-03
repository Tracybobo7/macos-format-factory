#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
TEST_BUILD_DIR="$PROJECT_ROOT/.build/tests"
MODULE_CACHE="$PROJECT_ROOT/.build/objc-module-cache"
HEIC_SAMPLE="${1:-}"

cd "$PROJECT_ROOT"
mkdir -p "$TEST_BUILD_DIR" "$MODULE_CACHE"

clang \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$MODULE_CACHE" \
    -mmacosx-version-min=13.0 \
    NativeFallback/FFConversionEngine.m \
    NativeFallback/FFIntegrationTests.m \
    -o "$TEST_BUILD_DIR/FFIntegrationTests" \
    -framework Foundation \
    -framework CoreGraphics \
    -framework ImageIO \
    -framework PDFKit

if [[ -n "$HEIC_SAMPLE" ]]; then
    "$TEST_BUILD_DIR/FFIntegrationTests" "$HEIC_SAMPLE"
else
    "$TEST_BUILD_DIR/FFIntegrationTests"
fi

