#!/bin/sh
set -eu

# Install base
apk update
apk add openrc
rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot
rc-update add networking default
rc-update add local default

# Install TTY
apk add agetty

# Setting up shell
apk add shadow
apk add bash bash-completion
chsh -s /bin/bash
echo -e "luckfox\nluckfox" | passwd
apk del -r shadow

apk add \
  dropbear \
  mtd-utils-ubi \
  bottom \
  ca-certificates \
  curl \
  fastfetch

rc-update add dropbear default
echo 'root:luckfox' | chpasswd

# Clear apk cache
rm -rf /var/cache/apk/*

echo "=== Copy Alpine rootfs ==="
for d in bin etc lib sbin usr var; do
  test -e "$d"
  tar c "$d" | tar x -C /extrootfs
done

for dir in dev proc root run sys tmp oem userdata; do
  mkdir -p "/extrootfs/$dir"
done

chmod 1777 /extrootfs/tmp

echo "=== Validate copied rootfs ==="
test -x /extrootfs/bin/busybox
test -x /extrootfs/usr/sbin/dropbear
test -x /extrootfs/etc/init.d/dropbear
test -d /extrootfs/var
test -d /extrootfs/etc

# Hand ownership to the host process while it applies the overlay. The build
# script restores root ownership before creating the archive.
chown -R "${HOST_UID:?}:${HOST_GID:?}" /extrootfs
