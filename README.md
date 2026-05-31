# PhoenixBoot

PhoenixBoot is a low-level watchdog designed to prevent permanent bricks and bootloops on rooted Android devices. It works by monitoring the boot cycle and automatically restoring a verified partition backup if the system fails to reach a stable state.

**Author:** Lysine000

## Core Features

### Kernel Panic Watchdog
The installer patches the boot image to include `panic=5` in the kernel cmdline. On a hard kernel panic, the device reboots immediately rather than hanging, allowing the watchdog to increment counters and eventually trigger recovery.

### Raw Partition Recovery
PhoenixBoot uses `dd` for block-level backups of the boot partition. Backups are SHA256 verified before any restore operation. The module attempts to store redundant copies in `/persist` or `/cache` to survive factory resets.

### Stability Window
After a successful boot, the watchdog waits 300 seconds. If the device remains up, panic counters are reset to 0.

## Installation

1. Flash the zip in Magisk, KernelSU, or APatch.
2. During installation, use the Volume Keys to confirm your bootloader status when prompted.
3. The module will backup your current boot image, patch the kernel parameters, and setup the watchdog services.

## Manual Recovery

Original boot images are stored at:
- `/data/adb/phoenixboot/boot_orig.img`
- `/persist/phoenixboot/boot_orig.img` (if supported)

If you need to restore manually from a shell:
`dd if=/data/adb/phoenixboot/boot_orig.img of=/dev/block/by-name/boot`
