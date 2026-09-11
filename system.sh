#!/bin/bash
set -euo pipefail

ROOTFS_NAME="rootfs-alpine.tar.gz"
DEVICE_NAME="pico-mini-b"
BUILD_STAGE="all"

while getopts ":f:d:s:" opt; do
  case ${opt} in
  f) ROOTFS_NAME="${OPTARG}" ;;
  d) DEVICE_NAME="${OPTARG}" ;;
  s) BUILD_STAGE="${OPTARG}" ;;
  ?)
    echo "Invalid option: -${OPTARG}."
    exit 1
    ;;
  esac
done

shift $((OPTIND - 1))

DEVICE_ID="6"
case $DEVICE_NAME in
pico-mini-b) DEVICE_ID="6" ;;
pico-plus) DEVICE_ID="7" ;;
pico-pro-max) DEVICE_ID="8" ;;
*)
  echo "Invalid device: ${DEVICE_NAME}."
  exit 1
  ;;
esac

case "$BUILD_STAGE" in all|board|userspace) ;; *) echo "Invalid stage: $BUILD_STAGE" >&2; exit 2 ;; esac

ROOTFS_PATH="$(realpath "$ROOTFS_NAME")"
ROOTFS_NAME="$(basename "$ROOTFS_PATH")"

rm -rf sdk/sysdrv/custom_rootfs/
mkdir -p sdk/sysdrv/custom_rootfs/
cp "$ROOTFS_PATH" "sdk/sysdrv/custom_rootfs/$ROOTFS_NAME"
test -f "sdk/sysdrv/custom_rootfs/$ROOTFS_NAME"

CUSTOM_ROOTFS="$(realpath "sdk/sysdrv/custom_rootfs/$ROOTFS_NAME")"

echo "Checking Alpine rootfs: $CUSTOM_ROOTFS"

tar tzf "$CUSTOM_ROOTFS" | grep -E '^\./bin/' >/dev/null || {
  echo "ERROR: Alpine rootfs has no /bin"
  tar tzf "$CUSTOM_ROOTFS" | head -100
  exit 1
}

pushd sdk || exit

CUSTOM_ROOTFS="$PWD/sysdrv/custom_rootfs/$ROOTFS_NAME"

echo "=== Custom rootfs ==="
echo "$CUSTOM_ROOTFS"
test -f "$CUSTOM_ROOTFS"

TOOLCHAIN_DIR="$PWD/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"

echo "=== Toolchain ==="
command -v arm-rockchip830-linux-uclibcgnueabihf-gcc
arm-rockchip830-linux-uclibcgnueabihf-gcc --version

rm -rf .BoardConfig.mk
echo "$DEVICE_ID" | ./build.sh lunch

CUSTOM_ROOTFS="$PWD/sysdrv/custom_rootfs/$ROOTFS_NAME"

export RK_CUSTOM_ROOTFS="$CUSTOM_ROOTFS"

printf '\nexport RK_CUSTOM_ROOTFS="%s"\n' \
  "$CUSTOM_ROOTFS" >>.BoardConfig.mk

printf 'export RK_BOOTARGS_CMA_SIZE="1M"\n' \
  >>.BoardConfig.mk

echo "=== Board config ==="
readlink -f .BoardConfig.mk
grep -E 'RK_CUSTOM_ROOTFS|RK_BOOTARGS_CMA_SIZE' .BoardConfig.mk

echo "=== Verify ==="
echo "RK_CUSTOM_ROOTFS=$RK_CUSTOM_ROOTFS"
test -f "$RK_CUSTOM_ROOTFS"

# build sysdrv - rootfs
if [ "$BUILD_STAGE" != userspace ]; then
  ./build.sh uboot
  ./build.sh kernel
  ./build.sh driver
  ./build.sh env
fi
#./build.sh app
# package firmware

ROOTFS_OUT="$PWD/output/out/rootfs_uclibc_rv1106"

echo "Staging Alpine rootfs into $ROOTFS_OUT"

rm -rf "$ROOTFS_OUT"
mkdir -p "$ROOTFS_OUT"

tar xzf "$CUSTOM_ROOTFS" -C "$ROOTFS_OUT"

test -d "$ROOTFS_OUT/bin" || {
  echo "ERROR: /bin missing after extracting Alpine rootfs"
  find "$ROOTFS_OUT" -maxdepth 2 -type d | sort
  exit 1
}

test -d "$ROOTFS_OUT/etc" || exit 1
test -d "$ROOTFS_OUT/usr" || exit 1

./build.sh firmware

test -f output/image/update.img

./build.sh save

popd || exit

mkdir -p ../output
cp sdk/output/image/update.img "../output/$DEVICE_NAME-sysupgrade.img"
