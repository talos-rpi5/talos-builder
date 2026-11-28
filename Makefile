PKG_VERSION = release-1.14
TALOS_VERSION = v1.14.7
SBCOVERLAY_VERSION = main

PKG_REF = a1a4897db70d69ca5b2d8466668b5d3f7d405840
TALOS_REF =
SBCOVERLAY_REF = 2309c3483b495039e5526418e595281b678e91c9

REGISTRY ?= ghcr.io
REGISTRY_USERNAME ?= talos-rpi5
PUSH ?= true

TAG ?= $(shell git describe --tags --exact-match)

EXTENSIONS ?= \
	ghcr.io/siderolabs/gvisor:20260831.0@sha256:7c6cdd8e52baca1ca21e0c8f8d241ba0cda0e687dd4a9ac12baa3adae89e832c \
	ghcr.io/siderolabs/iscsi-tools:v0.2.0@sha256:584e1d106e424d3e17ddd43bddf892b386748f10d11a9fd024a358f0d42c0a2e
EXTENSION_ARGS = $(foreach ext,$(EXTENSIONS),--system-extension-image=$(ext))

PKG_REPOSITORY = https://github.com/siderolabs/pkgs.git
TALOS_REPOSITORY = https://github.com/siderolabs/talos.git
SBCOVERLAY_REPOSITORY = https://github.com/talos-rpi5/sbc-raspberrypi5.git

CHECKOUTS_DIRECTORY := $(PWD)/checkouts
PATCHES_DIRECTORY := $(PWD)/patches

PKGS_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/pkgs && git describe --tag --always --dirty --match v[0-9]\*)
TALOS_TAG = $(TALOS_VERSION)
SBCOVERLAY_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5 && git describe --tag --always --dirty)-$(PKGS_TAG)

#
# Help
#
.PHONY: help
help:
	@echo "checkouts : Clone repositories required for the build"
	@echo "patches   : Apply all patches"
	@echo "kernel    : Build kernel"
	@echo "overlay   : Build Raspberry Pi 5 overlay"
	@echo "installer : Build installer docker image and disk image"
	@echo "netboot   : Build kernel/initramfs/cmdline assets (needs the pushed imager image)"
	@echo "netboot-ipxe : Generate boot.ipxe for the release (run after netboot)"
	@echo "release   : Use only when building the final release, this will tag relevant images with the current Git tag."
	@echo "clean     : Clean up any remains"



#
# Checkouts
#
.PHONY: checkouts checkouts-clean
checkouts:
	git clone -c advice.detachedHead=false --branch "$(PKG_VERSION)" "$(PKG_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/pkgs"
	git clone -c advice.detachedHead=false --branch "$(TALOS_VERSION)" "$(TALOS_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/talos"
	git clone -c advice.detachedHead=false --branch "$(SBCOVERLAY_VERSION)" "$(SBCOVERLAY_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5"
	$(if $(PKG_REF),git -C "$(CHECKOUTS_DIRECTORY)/pkgs" -c advice.detachedHead=false checkout -q "$(PKG_REF)")
	$(if $(TALOS_REF),git -C "$(CHECKOUTS_DIRECTORY)/talos" -c advice.detachedHead=false checkout -q "$(TALOS_REF)")
	$(if $(SBCOVERLAY_REF),git -C "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5" -c advice.detachedHead=false checkout -q "$(SBCOVERLAY_REF)")

checkouts-clean:
	rm -rf "$(CHECKOUTS_DIRECTORY)/pkgs"
	rm -rf "$(CHECKOUTS_DIRECTORY)/talos"
	rm -rf "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5"



#
# Patches
#
.PHONY: patches-pkgs patches-talos patches
patches-pkgs:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		git am $(sort $(wildcard $(PATCHES_DIRECTORY)/siderolabs/pkgs/*.patch))

patches-talos:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		git am $(sort $(wildcard $(PATCHES_DIRECTORY)/siderolabs/talos/*.patch))

patches: patches-pkgs patches-talos



#
# Kernel
#
.PHONY: kernel
kernel:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PLATFORM=linux/arm64 \
			kernel



#
# Overlay
#
.PHONY: overlay
overlay:
	@echo SBCOVERLAY_TAG = $(SBCOVERLAY_TAG)
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) IMAGE_TAG=$(SBCOVERLAY_TAG) PUSH=$(PUSH) \
			PKGS_PREFIX=$(REGISTRY)/$(REGISTRY_USERNAME) PKGS=$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			sbc-raspberrypi5



#
# Installer/Image
#
.PHONY: installer
installer:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			TAG=$(TALOS_TAG) \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			IMAGER_ARGS="--overlay-name=rpi5 --overlay-image=$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi5:$(SBCOVERLAY_TAG) $(EXTENSION_ARGS)" \
			kernel initramfs imager installer-base installer && \
		docker \
			run --rm -t -v ./_out:/out -v /dev:/dev --privileged $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) \
			rpi5 --arch arm64 \
			--base-installer-image="$(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG)" \
			--overlay-name="rpi5" \
			--overlay-image="$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi5:$(SBCOVERLAY_TAG)" \
			$(EXTENSION_ARGS)



#
# Netboot assets
#
# Reuses the pushed imager image; see scripts/netboot-asset.sh.
.PHONY: netboot
netboot:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		export REGISTRY=$(REGISTRY) REGISTRY_USERNAME=$(REGISTRY_USERNAME) \
			TALOS_TAG=$(TALOS_TAG) SBCOVERLAY_TAG=$(SBCOVERLAY_TAG) \
			EXTENSIONS="$(EXTENSIONS)" && \
		bash "$(CURDIR)/scripts/netboot-asset.sh" kernel ./_out/netboot/kernel && \
		bash "$(CURDIR)/scripts/netboot-asset.sh" initramfs ./_out/netboot/initramfs && \
		bash "$(CURDIR)/scripts/netboot-asset.sh" cmdline ./_out/netboot/cmdline

# Run after `netboot`. GITHUB_REPOSITORY is owner/repo.
.PHONY: netboot-ipxe
netboot-ipxe:
	cd "$(CHECKOUTS_DIRECTORY)/talos/_out/netboot" && \
		URL="https://github.com/$(GITHUB_REPOSITORY)/releases/download/$(TAG)" && \
		printf '#!ipxe\n\nimgfree\nkernel %s/%s %s\ninitrd %s/%s\nboot\n' \
			"$$URL" "$$(basename kernel/*)" "$$(cat cmdline/*)" \
			"$$URL" "$$(basename initramfs/*)" > boot.ipxe



#
# Release
#
.PHONY: release
release:
	docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TAG) && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TAG)



#
# Clean
#
.PHONY: clean
clean: checkouts-clean
