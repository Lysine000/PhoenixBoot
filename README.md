# Phoenix Boot 🛡️
**Zero-compromise bootloop protection for rooted Android.**

Phoenix Boot is a fail-safe watchdog for your Android device. It monitors the boot process and automatically restores your original boot image if it detects a crash cycle (bootloop). Unlike basic scripts, Phoenix Boot uses a two-tier verification system and can survive factory resets on supported hardware.

---

## ✨ Key Features

*   **Dual-Tier Watchdog:** 
    *   **Tier 1 (Early-Panic):** Uses a tiny 16-byte block in the `/misc` partition to catch loops before `/data` is even mounted.
    *   **Tier 2 (Stability Monitor):** Tracks rapid reboots within the first 90 seconds of the system starting up.
*   **Universal Compatibility:** Supports standard AOSP layouts, A/B devices, and GKI 2.0 (via `bootconfig` block patching).
*   **Factory-Reset Proof:** Automatically identifies and uses redundant backup locations in `/persist` or `/cache` to ensure your stock boot image survives a data wipe.
*   **Safe by Design:** 
    *   Strict SHA256 verification of all backups before flashing.
    *   Manual Volume Key confirmation for bootloader status to prevent accidental bricks on locked devices.

## 🛠️ How it Works

1.  **The Patch:** The installer uses `magiskboot` to inject `panic=5` into your kernel parameters. This ensures the device reboots instantly on a kernel panic rather than hanging on a black screen.
2.  **The Counter:** Every time the device starts, a service increments a persistent counter.
3.  **The Reset:** If the device remains stable for 5 minutes (the "Stability Window"), the watchdog marks the boot as successful and resets the counters.
4.  **The Rescue:** If the counter hits the limit (3 early panics or 5 rapid reboots), Phoenix Boot verifies your stock backup and flashes it back to the boot partition.

## 📥 Installation

1.  Flash the module zip in **Magisk**, **KernelSU**, or **APatch**.
2.  **Follow the Prompts:** During installation, you will be asked to confirm your bootloader status using the **Volume Keys**.
3.  The module will automatically handle the backup, patching, and verification.

## 🆘 Emergency Manual Recovery

If auto-recovery isn't triggered or fails for any reason, your original boot image is always safe. You can find it at:
- `/data/adb/phoenixboot/boot_orig.img`
- `/(persist|cache)/phoenixboot/boot_orig.img` (if available)

To restore manually via ADB or a custom recovery terminal:
```bash
# Replace 'boot' with your specific partition name if different
dd if=/data/adb/phoenixboot/boot_orig.img of=/dev/block/by-name/boot
```

## 🏗️ Building from Source

If you want to package the module yourself, use the included build script:
```bash
chmod +x build.sh
./build.sh
```

---
*Maintained with ❤️ by lysine*
