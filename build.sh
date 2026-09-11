#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="pico-pro-max"
COMMAND="all"

usage() { echo "Usage: $0 [doctor|rootfs|firmware|all] [-d device]"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    -d) DEVICE="${2:?device is required}"; shift 2 ;;
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
  docker build -f "$ROOT/docker/sdk.Dockerfile" -t luckfox-sdk-builder "$ROOT/docker"
  docker run --rm --platform linux/amd64 --privileged \
    -v "$ROOT:/work" -w /work \
    luckfox-sdk-builder bash -lc "./system.sh -f '$ROOTFS' -d '$DEVICE'"
  cp "$ROOT/output/$DEVICE-sysupgrade.img" "$ROOT/dist/$DEVICE-sysupgrade.img"
fi

echo "Artifacts are in $ROOT/dist"
