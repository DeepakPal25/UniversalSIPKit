#!/usr/bin/env bash
#
# create-xcframework.sh — combine the per-slice static libraries produced by
# build-baresip-ios.sh into Frameworks/Baresip.xcframework.
#
# The two simulator slices (arm64 + x86_64) must be merged with `lipo` into one
# fat library before being handed to xcodebuild, which rejects two same-platform
# slices. Device stays separate.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build-baresip/artifacts"
STAGE="$ROOT/.build-baresip/stage"
XCFRAMEWORK="$ROOT/Frameworks/Baresip.xcframework"

LIB_NAME="libBaresipCombined.a"

require() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' not found" >&2; exit 1; }; }
require lipo
require libtool
require xcodebuild

[ -d "$OUT" ] || { echo "error: $OUT missing — run build-baresip-ios.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$XCFRAMEWORK"
mkdir -p "$STAGE"

# Merge all .a files within a slice into a single archive (libtool), so the
# XCFramework exposes one library per platform.
combine_slice() {
  local slice="$1"
  local dir="$OUT/$slice"
  [ -d "$dir/lib" ] || { echo "error: $dir/lib missing" >&2; exit 1; }
  mkdir -p "$STAGE/$slice/Headers"
  libtool -static -o "$STAGE/$slice/$LIB_NAME" "$dir"/lib/*.a
  cp -R "$dir/include/." "$STAGE/$slice/Headers/" 2>/dev/null || true
}

combine_slice "ios-device"
combine_slice "ios-sim-arm64"
combine_slice "ios-sim-x86_64"

# Fat simulator library (arm64 + x86_64).
mkdir -p "$STAGE/ios-simulator/Headers"
lipo -create \
  "$STAGE/ios-sim-arm64/$LIB_NAME" \
  "$STAGE/ios-sim-x86_64/$LIB_NAME" \
  -output "$STAGE/ios-simulator/$LIB_NAME"
cp -R "$STAGE/ios-sim-arm64/Headers/." "$STAGE/ios-simulator/Headers/"

xcodebuild -create-xcframework \
  -library "$STAGE/ios-device/$LIB_NAME"    -headers "$STAGE/ios-device/Headers" \
  -library "$STAGE/ios-simulator/$LIB_NAME" -headers "$STAGE/ios-simulator/Headers" \
  -output "$XCFRAMEWORK"

echo "Created $XCFRAMEWORK"
echo
echo "Next:"
echo "  1. In Package.swift, add:"
echo "       .binaryTarget(name: \"Baresip\", path: \"Frameworks/Baresip.xcframework\")"
echo "     and add \"Baresip\" to the BaresipBridge target's dependencies."
echo "  2. Rebuild. BaresipBridge's #if __has_include(<baresip.h>) flips on and"
echo "     BaresipEngine.isEngineAvailable becomes true."
