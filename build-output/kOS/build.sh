#!/bin/bash
set -ex

echo "================================"
echo "DIAGNOSTIC: Initial disk space"
echo "================================"
df -h

apt-get update
apt-get install -y tree live-build debootstrap tar unar syslinux-utils \
    isolinux debian-archive-keyring rclone squashfs-tools genisoimage

mkdir -p /tmp/live-build
cd /tmp/live-build

echo "=================================="
echo "DIAGNOSTIC: Configuring live-build"
echo "=================================="

ls -lh

echo "Patching binary_bootloader_splash"
sed -i "s|_PROJECT=\"Debian GNU/Linux\"|_PROJECT=\"kazamOS\"\n_DISTRIBUTION=\"wired\"|g" /usr/lib/live/build/binary_bootloader_splash
cat /usr/lib/live/build/binary_bootloader_splash

lb config \
  --distribution trixie \
  --architectures amd64 \
  --debian-installer none \
  --archive-areas "main contrib non-free non-free-firmware" \
  --backports true \
  --security true \
  --updates true \
  --binary-images iso-hybrid \
  --bootappend-live "boot=live components live-config.timezone=Asia/Karachi locales=en_US.UTF-8,ur_PK.UTF-8 keyboard-layouts=us quiet splash" \
  --bootloader grub-pc,grub-efi \
  --uefi-secure-boot auto \
  --compression gzip \
  --chroot-squashfs-compression-type gzip \
  --initsystem systemd \
  --initramfs live-boot \
  --iso-application "kazamOS" \
  --iso-publisher "Kazam" \
  --iso-volume "kazamOS ISO"

mkdir -p config/package-lists
cp /output/kOS/packages.list config/package-lists/custom.list.chroot

mkdir -p config/hooks/normal
tree /output/ -L 3 || echo "/output doesn't exist"
cp /output/kOS/hooks/normal/000-setup.hook.chroot config/hooks/normal/000-setup.hook.chroot
cp /output/kOS/hooks/normal/001-datetime.hook.chroot config/hooks/normal/001-datetime.hook.chroot
cp /output/kOS/hooks/normal/010-am.hook.chroot config/hooks/normal/010-am.hook.chroot
cp /output/kOS/hooks/normal/020-apps.hook.chroot config/hooks/normal/020-apps.hook.chroot
cp /output/kOS/hooks/normal/020-themes.hook.chroot config/hooks/normal/020-themes.hook.chroot
cp /output/kOS/hooks/normal/999-desktop-config.hook.chroot config/hooks/normal/999-desktop-config.hook.chroot

mkdir -p config/includes.chroot/
cp -r /output/kOS/includes.chroot/etc config/includes.chroot/
cp -r /output/kOS/includes.chroot/usr config/includes.chroot/

tree config/ -L 3

echo "================================"
echo "DIAGNOSTIC: Starting build"
echo "================================"
df -h

lb build 2>&1 | tee /output/build.log

if [ -f binary/live/filesystem.squashfs ]; then
  echo "================================"
  echo "DIAGNOSTIC: Checking squashfs integrity"
  echo "================================"
  unsquashfs -s binary/live/filesystem.squashfs || echo "WARNING: squashfs check failed"
  ls -lh binary/live/filesystem.squashfs
  
  # Check if squashfs is suspiciously small
  SQFS_SIZE=$(stat -c%s binary/live/filesystem.squashfs)
  if [ "$SQFS_SIZE" -lt 2500000000 ]; then
    echo "ERROR: Squashfs is too small ($SQFS_SIZE bytes), expected >2.5GB"
  fi
else
  echo "ERROR: No filesystem.squashfs found!"
fi

# Check kernel and initrd
echo "================================"
echo "DIAGNOSTIC: Checking boot files"
echo "================================"
find binary -name "vmlinuz*" -o -name "initrd*" | xargs ls -lh

if [ -f *.iso ]; then
  ISO_FILE=$(ls *.iso | head -n 1)
  echo "================================"
  echo "DIAGNOSTIC: ISO created: $ISO_FILE"
  echo "================================"
  ls -lh "$ISO_FILE"
  
  # Verify ISO structure
  isoinfo -d -i "$ISO_FILE" | head -20
  
  # Check ISO size
  ISO_SIZE=$(stat -c%s "$ISO_FILE")
  echo "ISO size: $ISO_SIZE bytes ($(($ISO_SIZE / 1024 / 1024))M)"
  
  if [ "$ISO_SIZE" -lt 2000000000 ]; then
    echo "WARNING: ISO seems smaller than expected"
  fi
  
  cp *.iso /output/
else
  echo "ERROR: No ISO found"
  exit 1
fi

ls -lh /output/
