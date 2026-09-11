# Project instructions

This repository builds Alpine Linux firmware for Luckfox Pico boards.

- Use `./build.sh doctor` before diagnosing Docker or architecture problems.
- Use `./build.sh all -d pico-pro-max` for a clean end-to-end build.
- Use `-s userspace` for package/overlay changes and `-s board` for U-Boot,
  kernel, DTB, or vendor changes.
- The SDK is fetched at the pinned commit into the Docker volume
  `luckfox-sdk`; do not commit generated SDK output or build artifacts.
- Firmware output belongs in `dist/` and is ignored by Git.
- Keep the Alpine rootfs ARMv7 and the SDK builder linux/amd64.
- Run `bash -n build.sh rootfs.sh system.sh` after shell changes.
