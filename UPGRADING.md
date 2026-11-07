# Upgrading Talos
When a new version of Talos is released it may be necessary to adjust the patches we are applying to the upstream repositories.

1. Make sure you're starting from a clean slate
```
make clean
```
2. Update the versions in the _Makefile_.
```
TALOS_VERSION = vX.XX.X         <-- siderolabs/talos tag
PKG_VERSION = release-X.XX      <-- siderolabs/pkgs tag or branch
PKG_REF = <commit>              <-- optional commit pin, checked out after cloning PKG_VERSION
SBCOVERLAY_VERSION = main       <-- talos-rpi5/sbc-raspberrypi5 tag or branch
SBCOVERLAY_REF = <commit>       <-- optional commit pin
EXTENSIONS ?= <space separated list of ghcr.io/siderolabs/<extension>:<version>@sha256:<digest>>
```
   * Talos pins the exact pkgs version it was built with in its _Makefile_ (`PKGS ?= vX.XX.X-NN-g<sha>`).
     Use that commit for `PKG_REF` (and its release branch for `PKG_VERSION`) so the kernel matches upstream.
     After `make checkouts`, `git -C checkouts/pkgs describe --tags` must print the same value.
   * `*_REF` variables can be left empty when `*_VERSION` is a tag. A `TALOS_REF` is available as well.
   * Extension versions come from the `siderolabs/extensions` tag matching `TALOS_VERSION` (`<category>/<name>/vars.yaml`,
     e.g. `container-runtime/gvisor/vars.yaml`, `storage/iscsi-tools/vars.yaml`); resolve the (multi-arch) digest with
     `crane digest ghcr.io/siderolabs/<name>:<version>`. Extensions that need kernel support (e.g. iscsi-tools needs
     `ISCSI_TCP`/`SCSI_ISCSI_ATTRS`) must have it enabled in the kernel config, either built in or listed in _hack/modules-arm64.txt_.
3. Clone all checkouts
```
make checkouts
```
4. Update patches as outlined below
5. Commit and push changes
```
git commit -am 'Talos upgrade to vX.XX.X'
git push
```
6. Create new tag
```
git tag vX.XX.X-rpi5
git push origin vX.XX.X-rpi5
```

## Pkgs
The [siderolabs/pkgs](https://github.com/siderolabs/pkgs) repository produces a set of packages which is used to build the rootfs. We are concerned about customizing the Kernel package, by using the [raspberrypi/linux](https://github.com/raspberrypi/linux) kernel.

The patch changes three files:

| File | Change |
|---|---|
| `Pkgfile` | `linux_version` points to a raspberrypi/linux `stable_YYYYMMDD` tag, with matching `linux_sha256`/`linux_sha512` |
| `kernel/prepare/pkg.yaml` | Kernel source is downloaded from `https://github.com/raspberrypi/linux/archive/refs/tags/<tag>.tar.gz` and extracted with `tar -xzf` |
| `kernel/build/config-arm64` | Upstream config + RPi5 customizations, normalized with `olddefconfig` |

1. Try to apply the patch. If it applies, only bump the kernel tag (step 3) if desired.
```
make patches-pkgs
```
2. If it doesn't apply, start from the new upstream files and re-apply the `Pkgfile` / `kernel/prepare/pkg.yaml` edits by hand.
   Pick a raspberrypi/linux `stable_*` tag on the same kernel series as upstream pkgs (`linux_version` in the upstream `Pkgfile`).
3. Compute the checksums of the source tarball
```
curl -fsSLO https://github.com/raspberrypi/linux/archive/refs/tags/stable_YYYYMMDD.tar.gz
shasum -a 256 stable_YYYYMMDD.tar.gz
shasum -a 512 stable_YYYYMMDD.tar.gz
```
4. Regenerate `kernel/build/config-arm64`. **Do not hand-merge the old config diff**, it contains auto-generated symbols of the old kernel.
   1. Extract the RPi delta: check out the *previous* pkgs version, apply the *previous* patch, and diff the patched against the stock
      `kernel/build/config-arm64` (`scripts/diffconfig` from the kernel tree). Keep the intentional customizations
      (see list below); drop compiler/tool versions (`CC_VERSION_TEXT`, `PAHOLE_VERSION`), `HAVE_*`/`ARCH_HAS_*` selects and
      symbols which only differ because upstream changed them in the meantime. Save it as a fragment in `checkouts/` (not committed).
   2. Apply the fragment on top of the new upstream `kernel/build/config-arm64` (`scripts/kconfig/merge_config.sh -m`, or
      simply replace/append the lines).
   3. Normalize the config against the RPi kernel source (only arm64 is needed):
```
cd checkouts/pkgs
make local-kernel-build TARGET_ARGS="--build-arg=KERNEL_TARGET=olddefconfig" PLATFORM=linux/arm64 DEST="kernel/build"
```
   4. Verify every fragment symbol survived `olddefconfig` with the requested value. Symbols that were renamed/removed
      upstream or have unmet dependencies are dropped silently and need to be fixed by hand.
   5. Make sure the patches in `kernel/build/patches/` still apply to the RPi source (`git apply --check -p1 <patch>` in the extracted tarball).
5. Commit and regenerate the patch
```
cd checkouts/pkgs
git commit -am '[PATCH] Patched for Raspberry Pi 5'
git format-patch --output-directory "../../patches/siderolabs/pkgs" HEAD~1
```

### Intentional kernel config customizations
* `CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y`
* BCM2712/RP1 platform: `BCM2712_IOMMU`, `BCM2712_MIP`, `PINCTRL_BCM2712`, `MFD_RP1`, `FIRMWARE_RP1`, `MBOX_RP1`, `RP1_PIO`,
  `PINCTRL_RP1`, `COMMON_CLK_RP1(_SDIO)`, `PWM_RP1`, `PWM_PIO_RP1`, `WS2812_PIO_RP1`, `SPI_RP2040_GPIO_BRIDGE`
* Raspberry Pi peripherals: `BCM2835_THERMAL`, `BCM2835_SMI(_DEV)=m`, `RASPBERRYPI_GPIOMEM`, `NVMEM_RASPBERRYPI_OTP`, `RTC_DRV_RPI`,
  `MFD_RASPBERRYPI_POE_HAT`, `GPIO_BCM_VIRT`, `I2C_BCM2708`, `FB_BCM2708`, `FB_RPISENSE`, `PWM_BRCMSTB`, `PWM_GPIO`, `SPI_GPIO`,
  `PINCTRL_MCP23S08`, `NETWORK_PHY_TIMESTAMPING`
* RPi-only sound/video/panel/legacy drivers (`SND_BCM2708_SOC_*`, `VIDEO_RP1_CFE`, `USB_DWCOTG`, …) explicitly disabled
* Storage, NIC, HID, MMC and virtio drivers (NVMe, AHCI, igb/ixgbe/i40e/ice, r8169, tg3, stmmac, sdhci, …) built in (`=y`)
  instead of upstream's `=m`

The page size intentionally stays at upstream's 4K (`CONFIG_ARM64_4K_PAGES=y`), like every other Talos arm64 kernel. Don't carry
over `CONFIG_ARM64_16K_PAGES` from the RPi `bcm2712_defconfig`: 16K pages break userspace that assumes 4K pages and
drop 4K-only options (`THP_SWAP`, `MESON_SM`, `DRM_XE`, …). After `olddefconfig`,
`git diff <stock> -- kernel/build/config-arm64 | grep -E '^[-+].*(PAGE|VA_BITS|MAX_ORDER|CONT_P|MMAP_RND)'` must print nothing.

## Talos
The [siderolabs/talos](https://github.com/siderolabs/talos) repository is where packages and Talos come together. We'll need to customise the list of available kernel modules to be copied in to the initramfs.

`make patches` applies every `*.patch` in `patches/siderolabs/<repo>/` in sorted order. Currently the only talos patch
is `0001-Patched-for-Raspberry-Pi-5.patch` (RPi5 specific `hack/modules-arm64.txt`, regenerated on every upgrade, see below).

The disk image is generated with the overlay's `rpi5` imager profile (`profiles/rpi5/rpi5.yaml` in sbc-raspberrypi5,
`imager rpi5 ...` in the Makefile), like Image Factory does for upstream SBC overlays. It selects GRUB and `.xz` output.
Don't switch back to the `metal` profile: it uses sd-boot on arm64, and since Talos 1.14 sd-boot doesn't run the overlay
installer for disk images, so firmware, `u-boot.bin` and `config.txt` would be missing.

After building, check that the image's EFI partition contains `u-boot.bin`, `config.txt` and the firmware (`start4.elf`, `bcm2712-*.dtb`, `overlays/`), e.g. with `mdir -i metal-arm64.raw@@1M -/ ::/` (after `xz -d`). The image should have EFI, BIOS, BOOT and META partitions.

1. Try to apply the patches. If there are errors proceed to step 2, if not no further changes are needed.
```
make patches-talos
```
2. Build the kernel first (`make kernel`), the module list depends on the built kernel. Then regenerate _hack/modules-arm64.txt_:
   * extract `/usr/lib/modules/<version>/` from the kernel image (`docker create` + `docker cp`),
   * keep the `modules.builtin`, `modules.builtin.modinfo` and `modules.order` index files,
   * keep every entry of the upstream list, plus the RPi specific modules of the previous patch, that exists as `.ko`
     in the built tree (modules built in with `=y` disappear),
   * add the dependencies of every listed module (`modules.dep`): talos runs `depmod --errsyms -w` and fails on any warning.
```
cd checkouts/talos
cp <updated modules-arm64.txt> hack/modules-arm64.txt
git commit -am '[PATCH] Patched for Raspberry Pi 5'
git format-patch --output-directory "../../patches/siderolabs/talos" HEAD~1
```
