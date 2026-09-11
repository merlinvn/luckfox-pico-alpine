#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="pico-pro-max"
COMMAND="all"
STAGE="all"
SDK_URL="https://github.com/merlinvn/luckfox-pico-sdk.git"
SDK_COMMIT="06ddc0463e6f86edc6a659582bdcbbf64337798b"
DOCKER_CACHE_ARGS=()
if [ "${GITHUB_ACTIONS:-}" = true ]; then
  DOCKER_CACHE_ARGS=(--cache-from type=gha --cache-to type=gha,mode=max)
fi

usage() { echo "Usage: $0 [doctor|rootfs|firmware|all] [-d device] [-s all|board|userspace]"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    -d) DEVICE="${2:?device is required}"; shift 2 ;;
    -s) STAGE="${2:?stage is required}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    doctor|rootfs|firmware|all) COMMAND="$1"; shift ;;
    *) usage >&2; exit 2 ;;
  esac
done

case "$COMMAND" in
  doctor)
    command -v docker >/dev/null || { echo "Docker is required" >&2; exit 1; }
    docker version >/dev/null
    docker run --rm --platform linux/arm/v7 arm32v7/alpine:3.20 uname -m
    docker run --rm --platform linux/amd64 ubuntu:22.04 uname -m
    echo "Docker multi-platform support is ready"
    exit 0
    ;;
  rootfs|firmware|all) ;;
  *) usage >&2; exit 2 ;;
esac

mkdir -p "$ROOT/dist"
if [ "$COMMAND" = rootfs ] || [ "$COMMAND" = all ]; then
  "$ROOT/rootfs.sh"
  cp "$ROOT/output/rootfs-alpine.tar.gz" "$ROOT/dist/rootfs-alpine.tar.gz"
fi

if [ "$COMMAND" = firmware ] || [ "$COMMAND" = all ]; then
  ROOTFS="$ROOT/dist/rootfs-alpine.tar.gz"
  [ -f "$ROOTFS" ] || ROOTFS="$ROOT/output/rootfs-alpine.tar.gz"
  [ -f "$ROOTFS" ] || { echo "Rootfs archive not found; run rootfs first" >&2; exit 1; }
  docker buildx build --load --platform linux/amd64 ${DOCKER_CACHE_ARGS[@]-} \
    -f "$ROOT/docker/sdk.Dockerfile" -t luckfox-sdk-builder "$ROOT/docker"
  CONTAINER_ROOTFS="/work/dist/$(basename "$ROOTFS")"
  docker run --rm --platform linux/amd64 --privileged \
    -v "$ROOT:/work" -v luckfox-sdk:/work/sdk -w /work \
    -e SDK_URL="$SDK_URL" -e SDK_COMMIT="$SDK_COMMIT" \
    -e CONTAINER_ROOTFS="$CONTAINER_ROOTFS" -e DEVICE="$DEVICE" -e STAGE="$STAGE" \
    luckfox-sdk-builder -lc '
      set -e
      if [ ! -x /work/sdk/build.sh ]; then
        rm -rf /work/sdk/* /work/sdk/.[!.]* /work/sdk/..?* 2>/dev/null || true
        git clone --recurse-submodules "$SDK_URL" /work/sdk
        git -C /work/sdk checkout "$SDK_COMMIT"
        git -C /work/sdk submodule update --init --recursive
      fi
      if ! grep -q 'RK_CUSTOM_ROOTFS' /work/sdk/project/build.sh; then
        git -C /work/sdk apply /work/patches/sdk/0001-custom-rootfs.patch
      fi
      ./system.sh -f "$CONTAINER_ROOTFS" -d "$DEVICE" -s "$STAGE"
    '
  cp "$ROOT/output/$DEVICE-sysupgrade.img" "$ROOT/dist/$DEVICE-sysupgrade.img"
fi

echo "Artifacts are in $ROOT/dist"
