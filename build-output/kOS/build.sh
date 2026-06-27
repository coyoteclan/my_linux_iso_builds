#!/bin/bash
set -ex

echo "================================"
echo "DIAGNOSTIC: Initial disk space"
echo "================================"
df -h

apt-get update
apt-get install -y tree live-build debootstrap tar unar syslinux-utils \
    isolinux squashfs-tools genisoimage binutils gnupg2 patch zstd

mkdir -p /tmp/live-build
cd /tmp/live-build

echo "=================================="
echo "DIAGNOSTIC: Configuring live-build"
echo "=================================="


# COPIED FROM ELEMENTARY
# The Debian repositories don't seem to have the `ubuntu-keyring` or `ubuntu-archive-keyring` packages
# anymore, so we add the archive keys manually. This may need to be updated if Ubuntu changes their signing keys
# To get the current key ID, find `ubuntu-keyring-xxxx-archive.gpg` in /etc/apt/trusted.gpg.d on a running
# system and run `gpg --keyring /etc/apt/trusted.gpg.d/ubuntu-keyring-xxxx-archive.gpg --list-public-keys `
gpg --homedir /tmp --no-default-keyring --keyring /etc/apt/trusted.gpg --recv-keys --keyserver keyserver.ubuntu.com F6ECB3762474EDA9D21B7022871920D1991BC93C

# TODO: Remove this once debootstrap can natively build resolute images:
ln -sfn /usr/share/debootstrap/scripts/gutsy /usr/share/debootstrap/scripts/resolute

ls -lh

echo "Patching binary_bootloader_splash"
sed -i "s|_PROJECT=\"Debian GNU/Linux\"|_PROJECT=\"kazamOS\"\n_DISTRIBUTION=\"voltage\"|g" /usr/lib/live/build/binary_bootloader_splash
cat /usr/lib/live/build/binary_bootloader_splash

. /output/kOS/terraform.conf


if [ "$HWE_KERNEL" = "yes" ]; then
    KERNEL_FLAVORS="generic-hwe-${BASEVERSION}"
else
    KERNEL_FLAVORS="generic"
fi

if [ "$HWE_X11" = "yes" ]; then
    XORG_HWE="xserver-xorg-hwe-${BASEVERSION}"
fi

case "$ARCH" in
    amd64|i386)
        MIRROR_BINARY_URL="http://archive.ubuntu.com/ubuntu/"
        MIRROR_BINARY_SECURITY_URL="http://security.ubuntu.com/ubuntu/"
        ;;
    arm64)
        MIRROR_BINARY_URL="http://ports.ubuntu.com/ubuntu-ports/"
        MIRROR_BINARY_SECURITY_URL="http://ports.ubuntu.com/ubuntu-ports/"
        ;;
esac

lb config \
  --distribution "$BASECODENAME" \
  --parent-distribution "$BASECODENAME" \
  --architectures "$ARCH" \
  --mode debian \
  --debian-installer none \
  --archive-areas "main restricted universe multiverse" \
  --parent-archive-areas "main restricted universe multiverse" \
  --linux-packages linux-image \
  --linux-flavours "$KERNEL_FLAVORS" \
  --debootstrap-options="--extractor=ar --keyring=/etc/apt/trusted.gpg" \
  --checksums md5 \
  --mirror-bootstrap "$MIRROR_URL" \
  --parent-mirror-bootstrap "$MIRROR_URL" \
  --mirror-chroot-security "$MIRROR_BINARY_SECURITY_URL" \
  --parent-mirror-chroot-security "$MIRROR_BINARY_SECURITY_URL" \
  --mirror-binary-security "$MIRROR_BINARY_SECURITY_URL" \
  --parent-mirror-binary-security "$MIRROR_BINARY_SECURITY_URL" \
  --mirror-binary "$MIRROR_BINARY_URL" \
  --parent-mirror-binary "$MIRROR_BINARY_URL" \
  --keyring-packages ubuntu-keyring \
  --apt-options "--yes --option Acquire::Retries=2 --option Acquire::http::Timeout=45" \
  --cache-packages false \
  --uefi-secure-boot enable \
  --binary-images iso-hybrid \
  --bootappend-live "boot=live components live-config.timezone=Asia/Karachi locales=en_US.UTF-8,ur_PK.UTF-8 keyboard-layouts=us quiet splash" \
  --bootloader grub-pc,grub-efi \
  --uefi-secure-boot auto \
  --compression xz \
  --chroot-squashfs-compression-type xz \
  --initsystem systemd \
  --initramfs live-boot \
  --iso-application "$NAME" \
  --iso-volume "$NAME" \
  --iso-publisher "Kazam" \
  --security true

sed -i "s/@XORG_HWE/$XORG_HWE/" /output/kOS/packages.list
sed -i "s/@KERNEL_HEADERS/linux-headers-$KERNEL_FLAVORS/" /output/kOS/packages.list

mkdir -p config/package-lists
cp /output/kOS/packages.list config/package-lists/custom.list.chroot
#cp /output/kOS/binary.list config/package-lists/pool.list.binary

mkdir -p config/hooks/normal
tree /output/ -L 3 || echo "/output doesn't exist"
cp /output/kOS/hooks/normal/000-setup.hook.chroot config/hooks/normal/000-setup.hook.chroot
cp /output/kOS/hooks/normal/001-datetime.hook.chroot config/hooks/normal/001-datetime.hook.chroot
cp /output/kOS/hooks/normal/010-am.hook.chroot config/hooks/normal/010-am.hook.chroot
cp /output/kOS/hooks/normal/020-apps.hook.chroot config/hooks/normal/020-apps.hook.chroot
cp /output/kOS/hooks/normal/020-themes.hook.chroot config/hooks/normal/020-themes.hook.chroot
cp /output/kOS/hooks/normal/999-desktop-config.hook.chroot config/hooks/normal/999-desktop-config.hook.chroot
cp /output/kOS/hooks/normal/999-local-repo.hook.chroot config/hooks/normal/999-local-repo.hook.chroot

mkdir -p config/includes.chroot/
cp -r /output/kOS/includes.chroot/etc config/includes.chroot/
cp -r /output/kOS/includes.chroot/usr config/includes.chroot/

tree config/ -L 3

echo "================================"
echo "DIAGNOSTIC: Starting build"
echo "================================"
df -h

lb build 2>&1 | tee /output/build.log

apt install asciinema
asciinema rec /output/demo.cast

echo "================================"
echo "DIAGNOSTIC: Chroot size breakdown"
echo "================================"
du -sh /tmp/live-build/chroot/* | sort -h | tail -30
du -sh /tmp/live-build/chroot/usr/share/* | sort -h | tail -20
for f in /tmp/live-build/chroot/usr/share/*; do
  du -sh $f/* | sort -h | tail -20
done
du -sh /tmp/live-build/chroot/usr/lib/* | sort -h | tail -20
for f in /tmp/live-build/chroot/usr/lib/*; do
  du -sh $f/* | sort -h | tail -20
done

du -hs /opt/*

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
exit
