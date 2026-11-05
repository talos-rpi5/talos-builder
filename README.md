# Raspberry Pi 5 Talos Builder
This repository serves as the glue to build custom Talos images for the Raspberry Pi 5. It patches the Kernel and Talos build process to use the Linux Kernel source provided by [raspberrypi/linux](https://github.com/raspberrypi/linux). 

## Tested on
So far, this release has been verified on:

| ✅ Hardware                                                |
|------------------------------------------------------------|
| Raspberry Pi Compute Module 5 on Compute Module 5 IO Board |
| Raspberry Pi Compute Module 5 Lite on [DeskPi Super6C](https://wiki.deskpi.com/super6c/) |
| Raspberry Pi 5b with [RS-P11 for RS-P22 RPi5](https://wiki.52pi.com/index.php?title=EP-0234) |

## What's not working?
* Booting from USB: USB is only available once LINUX has booted up but not in U-Boot.

## How to use?
The releases on this repository align with the corresponding Talos version. There is a raw disk image (initial setup) and an installer image (upgrades) provided. 

### Examples
Initial:
```
xz -d metal-arm64.raw.xz
dd if=metal-arm64.raw of=<disk> bs=4M status=progress
sync
```
Alternatively flash `metal-arm64.raw.xz` directly with Raspberry Pi Imager or balenaEtcher. The disk image uses GRUB as bootloader (U-Boot → GRUB → Talos), same as the upstream Sidero Labs SBC images.

Upgrade:
```
talosctl upgrade \
  --nodes <node IP> \
  --image ghcr.io/talos-rpi5/installer:<version>
```

## Building
If you'd like to make modifications, it is possible to create your own build. Bellow is an example of the standard build.

```
# Clones all dependencies and applies the necessary patches
make checkouts patches

# Builds the Linux Kernel (can take a while)
make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> kernel

# Builds the overlay (U-Boot, dtoverlays ...)
make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> overlay

# Final step to build the installer and disk image
make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> installer
```
The disk image is written to `checkouts/talos/_out/metal-arm64.raw.xz`. All three steps push images to `REGISTRY/REGISTRY_USERNAME`.

## License
See [LICENSE](LICENSE).
