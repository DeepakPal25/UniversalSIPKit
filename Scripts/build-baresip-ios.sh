#!/usr/bin/env bash
#
# build-baresip-ios.sh — build libre + baresip as static libraries for each
# iOS slice (device arm64, simulator arm64, simulator x86_64), ready to be
# packaged into an XCFramework by create-xcframework.sh.
#
# This is a PoC build scaffold. It documents the intended steps; the exact
# cmake/flags for baresip evolve, so treat the TODOs as the verification points
# called out in docs/BARESIP-POC.md.
#
# Prereqs: Xcode + command line tools, cmake. Clone libre and baresip into
# Vendor/ first (see Vendor/README.md).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Vendor"
BUILD="$ROOT/.build-baresip"
OUT="$BUILD/artifacts"

LIBRE_SRC="$VENDOR/re"
BARESIP_SRC="$VENDOR/baresip"

MIN_IOS="15.0"

# slice name -> sdk, arch
SLICES=(
  "ios-device:iphoneos:arm64"
  "ios-sim-arm64:iphonesimulator:arm64"
  "ios-sim-x86_64:iphonesimulator:x86_64"
)

require() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' not found" >&2; exit 1; }; }
require cmake
require xcrun

[ -d "$LIBRE_SRC" ]   || { echo "error: $LIBRE_SRC missing — see Vendor/README.md" >&2; exit 1; }
[ -d "$BARESIP_SRC" ] || { echo "error: $BARESIP_SRC missing — see Vendor/README.md" >&2; exit 1; }

mkdir -p "$OUT"

build_slice() {
  local name="$1" sdk="$2" arch="$3"
  local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local slice_out="$OUT/$name"
  mkdir -p "$slice_out/lib" "$slice_out/include"

  echo "==> Building slice $name ($sdk/$arch)"

  # --- libre -------------------------------------------------------------
  # TODO(PoC): verify libre's current cmake options for iOS cross-compile.
  cmake -S "$LIBRE_SRC" -B "$BUILD/$name/re" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF
  cmake --build "$BUILD/$name/re" --config Release

  # --- baresip -----------------------------------------------------------
  # TODO(PoC): point baresip at the libre build; select the module set.
  # For the PoC keep modules minimal and royalty-free:
  #   g711, opus (optional), stun, turn, ice, srtp, aufile/coreaudio.
  cmake -S "$BARESIP_SRC" -B "$BUILD/$name/baresip" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DRE_SRC="$LIBRE_SRC"
  cmake --build "$BUILD/$name/baresip" --config Release

  # --- collect -----------------------------------------------------------
  # TODO(PoC): copy the produced .a files and public headers here. The exact
  # output paths depend on the cmake version; verify and fix the globs.
  find "$BUILD/$name" -name '*.a' -exec cp {} "$slice_out/lib/" \;
  cp -R "$LIBRE_SRC/include/." "$slice_out/include/" 2>/dev/null || true
  cp -R "$BARESIP_SRC/include/." "$slice_out/include/" 2>/dev/null || true

  echo "==> Slice $name -> $slice_out"
}

for entry in "${SLICES[@]}"; do
  IFS=':' read -r name sdk arch <<< "$entry"
  build_slice "$name" "$sdk" "$arch"
done

echo "All slices built under $OUT"
echo "Next: Scripts/create-xcframework.sh"
