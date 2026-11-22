#!/usr/bin/env bash
set -euo pipefail

# Builds one netboot asset (kind: kernel|initramfs|cmdline) into <output-dir>.
# `outFormat: raw` overrides the rpi5 profile's .xz, which breaks initramfs and
# double-compresses kernel.
# Usage: netboot-asset.sh <kind> <output-dir>
# Env: REGISTRY, REGISTRY_USERNAME, TALOS_TAG, SBCOVERLAY_TAG, EXTENSIONS

KIND="$1"
OUT_DIR="$2"

EXT_YAML=""
for ext in $EXTENSIONS; do
  EXT_YAML="$EXT_YAML    - imageRef: $ext
"
done

mkdir -p "$OUT_DIR"

docker run --rm -i -v "$OUT_DIR:/out" "$REGISTRY/$REGISTRY_USERNAME/imager:$TALOS_TAG" - <<PROFILE
baseProfile: rpi5
arch: arm64
version: $TALOS_TAG
input:
  baseInstaller:
    imageRef: $REGISTRY/$REGISTRY_USERNAME/installer:$TALOS_TAG
  systemExtensions:
$EXT_YAML
overlay:
  name: rpi5
  image:
    imageRef: $REGISTRY/$REGISTRY_USERNAME/sbc-raspberrypi5:$SBCOVERLAY_TAG
output:
  kind: $KIND
  outFormat: raw
PROFILE
