#!/usr/bin/env bash
set -euo pipefail

# Builds one netboot asset (kernel, initramfs, or cmdline) by feeding
# `imager` a minimal custom profile over stdin instead of using the
# `rpi5` named profile's CLI shortcut (`imager rpi5 --output-kind=...`).
#
# That named profile bakes in `output.outFormat: .xz` (sensible for the
# full disk-image build), and `--output-kind` only overrides the output
# *kind* -- `outFormat` carries straight through with no CLI flag to
# override it (checked directly against imager's own CLI code,
# cmd/installer/cmd/imager/root.go: no --output-format flag exists).
# `imager` always runs a second, generic compression pass keyed off
# outFormat after writing the kind-specific output (pkg/imager/imager.go,
# Execute(), step 6). For `initramfs`, whose own filename already ends in
# `.xz` (profile.OutputPath()'s naming for that kind), that second pass
# collides with itself: `xz: ...: File already has '.xz' suffix,
# skipping`, exit 2 -- the actual failure this script exists to avoid.
# For `kernel` the same pass "succeeds" but silently wraps the vmlinuz in
# an extra .xz layer that iPXE's `kernel` directive can't decompress on
# load, so that output was wrong too, just without a crash to notice it.
#
# `outFormat: raw` in the profile below skips that second pass entirely,
# for all three kinds -- the vmlinuz comes out exactly as the installer
# image ships it, and the initramfs (itself already real xz-compressed
# cpio data, the normal Linux initrd format) isn't wrapped a second time.
#
# input.kernel.path / input.initramfs.path are the fixed, conventional
# paths every Talos installer image ships at (confirmed against the
# profile imager itself printed while resolving the `rpi5` named
# profile) -- not something this script computes per build.
#
# Usage: netboot-asset.sh <kind> <output-dir>
#   kind: kernel | initramfs | cmdline
#
# Reads REGISTRY, REGISTRY_USERNAME, TALOS_TAG, SBCOVERLAY_TAG,
# EXTENSIONS (space-separated image refs) from the environment -- same
# variables the Makefile already computes for every other target.

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
