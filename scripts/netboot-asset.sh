#!/usr/bin/env bash
set -euo pipefail

# Builds one netboot asset (kernel, initramfs, or cmdline) by feeding imager a
# minimal profile on stdin, rather than `imager rpi5 --output-kind=...`.
#
# The rpi5 profile sets outFormat: .xz and imager has no flag to override it.
# That makes imager's second compression pass fail on initramfs (name already
# ends in .xz) and silently wrap kernel in an .xz that iPXE can't decompress.
# `outFormat: raw` skips that pass.
#
# Usage: netboot-asset.sh <kind> <output-dir>   (kind: kernel|initramfs|cmdline)
# Reads REGISTRY, REGISTRY_USERNAME, TALOS_TAG, SBCOVERLAY_TAG, EXTENSIONS
# from the environment, as set by the Makefile.

KIND="$1"
OUT_DIR="$2"

EXT_YAML=""
for ext in $EXTENSIONS; do
  EXT_YAML="$EXT_YAML    - imageRef: $ext
"
done

mkdir -p "$OUT_DIR"

docker run --rm -i -v "$OUT_DIR:/out" "$REGISTRY/$REGISTRY_USERNAME/imager:$TALOS_TAG" - <<PROFILE
arch: arm64
platform: metal
version: $TALOS_TAG
input:
  kernel:
    path: /usr/install/arm64/vmlinuz
  initramfs:
    path: /usr/install/arm64/initramfs.xz
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
