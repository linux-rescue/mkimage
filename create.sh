#!/bin/sh
# linux-rescue/mkimage/create.sh

# Required packages:
# base libisoburn syslinux arch-install-scripts squashfs-tools mtools dosfstools coreutils
ROOTFS_PACKAGES="archlinux-keyring file gcc-libs util-linux xz ncurses glibc iproute2 procps-ng iputils filesystem systemd systemd-sysvcompat util-linux kmod coreutils linux mkinitcpio bash iwd"  # Python, firmware and much more later...


# Empty directory for the bootable image (Hybrid ISO root) (recreate)
IMG_DIR=./iso.dir
[ ! -d "${IMG_DIR}" ] || rm -rf "${IMG_DIR}"
mkdir -p "${IMG_DIR}"


# Ship the build log in the target too.
BUILD_LOG="${IMG_DIR}/iso-build.log"


init_blog()
{
	echo "$1" | tee "${BUILD_LOG}"
}

blog()
{
	echo "$1" | tee -a "${BUILD_LOG}"
}

init_blog "Started Linux Rescue create.sh on $(date)."


# Existing source directory containing file hierarchy and script files from repository
SRC_DIR=./src
[ -d "${SRC_DIR}" ] || echo "SRC_DIR '${SRC_DIR}' not found."


# Temporary directory for contents of the rootfs image file (recreate)
ROOTFS_DIR=./rootfs.dir
[ ! -d "${ROOTFS_DIR}" ] || rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"


# rootfs image file destination in the image.
ROOTFS_FILE="${IMG_DIR}/rootfs.squashfs"


# Final hybrid ISO image for distribution.
ISO_FILE=./lrescue.iso


# Temp directory (recreate)
TMP_DIR=./temp
blog "Create/clean ${TMP_DIR}"
[ ! -d "${TMP_DIR}" ] || rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"


# Cache directory for downloads etc. (create, keep)
CACHE_DIR=./cache
blog "Create/keep CACHE_DIR: ${CACHE_DIR}"
mkdir -p "${CACHE_DIR}"




blog "Copy static source files to image..."
cp -rv "${SRC_DIR}/iso/." "${IMG_DIR}/" | tee -a "${BUILD_LOG}"


# systemd-boot
cp -v "/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "${IMG_DIR}/EFI/BOOT/BOOTX64.EFI" | tee -a "${BUILD_LOG}"


# syslinux files
cp -v /usr/lib/syslinux/bios/{isolinux.bin,ldlinux.c32,isohdpfx.bin} "${IMG_DIR}/isolinux/" | tee -a "${BUILD_LOG}"

# Preinstall some config files and directories:
cp -rv "${SRC_DIR}/etc" "${ROOTFS_DIR}/" | tee -a "${BUILD_LOG}"

mkdir -p "${ROOTFS_DIR}/etc/systemd/system/initrd-root-fs.target.wants"
ln -sf ../initrd-lrescue-root.service "${ROOTFS_DIR}/etc/systemd/system/initrd-root-fs.target.wants/initrd-lrescue-root.service"

pacstrap -cM "${ROOTFS_DIR}" $ROOTFS_PACKAGES

blog "Clean caches after pacstrap."
rm -rf \
	"${ROOTFS_DIR}/var/cache/pacman/pkg" \
	"${ROOTFS_DIR}/var/lib/pacman/sync" \
	"${ROOTFS_DIR}/usr/share/man" \
	"${ROOTFS_DIR}/usr/share/doc" \
	"${ROOTFS_DIR}/usr/share/info"


# Move kernel and initramfs into ISO root.
mv ${ROOTFS_DIR}/boot/* ${IMG_DIR}/boot/

# Create rootfs
blog "Compressing rootfs into squashfs file..."
mksquashfs "${ROOTFS_DIR}" "${ROOTFS_FILE}" -comp xz -no-progress 2>&1 | tee -a "${BUILD_LOG}"


blog "Creating efiboot.img..."
EFIBOOT_IMG="${IMG_DIR}/efiboot.img"
dd if=/dev/zero "of=${EFIBOOT_IMG}" bs=1M count=50 2>&1 | tee -a "${BUILD_LOG}"

blog "Creating efiboot.img file system..."
mkfs.fat -F32 -n LRESCUE_EFI "${EFIBOOT_IMG}" 2>&1 | tee -a "${BUILD_LOG}"

blog "Creating efiboot.img directories..."
mmd -i "${EFIBOOT_IMG}" ::/EFI 2>&1 | tee -a "${BUILD_LOG}"
mmd -i "${EFIBOOT_IMG}" ::/EFI/BOOT 2>&1 | tee -a "${BUILD_LOG}"
mmd -i "${EFIBOOT_IMG}" ::/loader 2>&1 | tee -a "${BUILD_LOG}"
mmd -i "${EFIBOOT_IMG}" ::/loader/entries 2>&1 | tee -a "${BUILD_LOG}"

blog "Add efiboot.img files..."
mcopy -i "${EFIBOOT_IMG}" "${IMG_DIR}/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/ 2>&1 | tee -a "${BUILD_LOG}"
mcopy -i "${EFIBOOT_IMG}" "${IMG_DIR}/EFI/BOOT/loader/loader.conf" ::/loader/ 2>&1 | tee -a "${BUILD_LOG}"
mcopy -i "${EFIBOOT_IMG}" "${IMG_DIR}/EFI/BOOT/loader/entries/lrescue.conf" ::/loader/entries/ 2>&1 | tee -a "${BUILD_LOG}"


blog "Compose ISO image..."
xorriso -as mkisofs \
  -iso-level 3 \
  -V LRESCUEISO \
  -o "${ISO_FILE}" \
  -isohybrid-mbr /usr/lib/syslinux/bios/isohdpfx.bin \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
  -eltorito-alt-boot \
  -e efiboot.img \
    -no-emul-boot \
  -isohybrid-gpt-basdat \
  "${IMG_DIR}" 2>&1 | tee -a "${BUILD_LOG}"

blog "Image ${IMG_DIR} ready."
