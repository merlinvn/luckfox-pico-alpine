#!/bin/bash
set -euo pipefail
OUTPUT_DIR="output"
ROOTFS_FILE="rootfs-alpine.tar.gz"

ROOTFS_WORKSPACE_MNT="$(mktemp -d "${TMPDIR:-/tmp}/luckfox-rootfs.XXXXXX")"

rootfs_workspace_drop() {
  if [ -d "$ROOTFS_WORKSPACE_MNT" ]; then
    docker run --rm --user 0 --platform linux/arm/v7 \
      --mount type=bind,source="$ROOTFS_WORKSPACE_MNT",target=/extrootfs \
      arm32v7/alpine:3.20 \
      sh -c 'find /extrootfs -mindepth 1 -delete' >/dev/null 2>&1 || true
    rm -rf "$ROOTFS_WORKSPACE_MNT"
  fi
}

trap rootfs_workspace_drop EXIT

mkdir -p "$ROOTFS_WORKSPACE_MNT"

echo "=== Test ARMv7 container ==="
docker run --rm \
  --platform linux/arm/v7 \
  arm32v7/alpine:3.20 \
  uname -a

echo "=== Build Alpine rootfs ==="
docker build --platform linux/arm/v7 \
  -f "$(pwd)/docker/rootfs.Dockerfile" \
  -t luckfox-rootfs:3.20 "$(pwd)"
docker rm -f armv7alpine 2>/dev/null || true

docker run --rm \
  --name armv7alpine \
  --platform linux/arm/v7 \
  --net host \
  --env HOST_UID="$(id -u)" --env HOST_GID="$(id -g)" \
  --mount type=bind,source="$(pwd)/bootstrap.sh",target=/bootstrap.sh,readonly \
  --mount type=bind,source="$ROOTFS_WORKSPACE_MNT",target=/extrootfs \
  luckfox-rootfs:3.20 \
  /bootstrap.sh

echo "=== Validate generated rootfs ==="
test -x "$ROOTFS_WORKSPACE_MNT/bin/busybox"
test -d "$ROOTFS_WORKSPACE_MNT/etc"
test -d "$ROOTFS_WORKSPACE_MNT/lib"
test -d "$ROOTFS_WORKSPACE_MNT/sbin"
test -d "$ROOTFS_WORKSPACE_MNT/usr"

# Configuring rootfs and overlay
overlay() {
  local OVERLAY_WORKSPACE="overlay-workspace"
  rm -rf "$OVERLAY_WORKSPACE"
  cp -R overlay "$OVERLAY_WORKSPACE"

  HOSTNAME="luckfox"
  sed -i -e "s/{HOSTNAME}/$HOSTNAME/g" "$OVERLAY_WORKSPACE/etc/hostname"

  TTY_PORT="ttyFIQ0"
  sed -i -e "s/{TTY_PORT}/$TTY_PORT/g" "$OVERLAY_WORKSPACE/etc/securetty"
  sed -i -e "s/{TTY_PORT}/$TTY_PORT/g" "$OVERLAY_WORKSPACE/etc/inittab"

  rsync -a --no-owner --no-group "$OVERLAY_WORKSPACE/" "$ROOTFS_WORKSPACE_MNT/"
  rm -rf "$OVERLAY_WORKSPACE"

  ln -sfn "/etc/init.d/00_link_mount" \
    "$ROOTFS_WORKSPACE_MNT/etc/runlevels/default/00_link_mount"

  ln -sfn "/etc/init.d/10_usb_gadget" \
    "$ROOTFS_WORKSPACE_MNT/etc/runlevels/default/10_usb_gadget"
}

overlay

# Restore root ownership only after the host overlay has been applied.
docker run --rm --user 0 --platform linux/arm/v7 \
  --mount type=bind,source="$ROOTFS_WORKSPACE_MNT",target=/extrootfs \
  arm32v7/alpine:3.20 \
  sh -c 'find /extrootfs -mindepth 1 ! -type l -exec chown 0:0 {} +'

echo "=== Validate final rootfs ==="

test -x "$ROOTFS_WORKSPACE_MNT/bin/busybox"
test -x "$ROOTFS_WORKSPACE_MNT/usr/sbin/dropbear"
test -x "$ROOTFS_WORKSPACE_MNT/etc/init.d/dropbear"

test -d "$ROOTFS_WORKSPACE_MNT/etc"
test -d "$ROOTFS_WORKSPACE_MNT/lib"
test -d "$ROOTFS_WORKSPACE_MNT/sbin"
test -d "$ROOTFS_WORKSPACE_MNT/usr"
test -d "$ROOTFS_WORKSPACE_MNT/var"
test -d "$ROOTFS_WORKSPACE_MNT/tmp"

test -L "$ROOTFS_WORKSPACE_MNT/etc/runlevels/default/dropbear"

rm -rf "$ROOTFS_WORKSPACE_MNT/lost+found"

# Packaging
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR"
docker run --rm --user 0 --platform linux/arm/v7 \
  --mount type=bind,source="$ROOTFS_WORKSPACE_MNT",target=/extrootfs,readonly \
  --mount type=bind,source="$(pwd)/$OUTPUT_DIR",target=/out \
  arm32v7/alpine:3.20 \
  tar czf "/out/$ROOTFS_FILE" -C /extrootfs .

echo "=== Rootfs archive ==="
ls -lh "$OUTPUT_DIR/$ROOTFS_FILE"

echo "=== Verify archive ==="
tar tzf "$OUTPUT_DIR/$ROOTFS_FILE" | sed -n '1,30p'

test "$(tar tzf "$OUTPUT_DIR/$ROOTFS_FILE" |
  grep -c '^\./bin/busybox$')" -eq 1

echo "Alpine rootfs created successfully."
