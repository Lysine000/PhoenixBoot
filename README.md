# 🔥 PhoenixBoot v1.2 (Enhanced Edition)
### Enterprise-Grade Universal Android Bootloop Protection

PhoenixBoot acts as an automated, zero-compromise safety net for your rooted Android device. It patches your active boot image with `panic=5` (forcing a hardware reboot 5 seconds after a kernel crash) and deploys an advanced two-tier watchdog to detect rapid reboot cycles or system hangs.

If a bootloop is detected, PhoenixBoot automatically restores your pristine, original boot image from a factory-reset-safe backup before data corruption or a soft brick occurs. Like a phoenix rising from the ashes.

---

## 🛡️ v1.2 Architecture Upgrades

Traditional bootloop protectors rely on legacy scripts that fail on modern devices or cause hard bricks. PhoenixBoot v1.2 has been entirely re-engineered to solve these fatal flaws:

* **The "panic=5" Paradox Solved:** Standard watchdogs are wiped from RAM during a kernel panic reboot, meaning they never trigger. PhoenixBoot fixes this by injecting an early-init service (`boot_abort_handler.sh`) that writes a persistent panic counter directly to the `/misc` block device. It tracks early kernel panics *before* the data partition even mounts.
* **True AVB & Locked Bootloader Safety:** Standard scripts blindly modify boot images, instantly hard-bricking locked devices. PhoenixBoot uses a defense-in-depth, multi-signal hardware check to verify your bootloader status. If it detects an enforced lock, it safely falls back into "Monitor-Only" mode.
* **Factory Reset Survival (Dual Backup):** Storing backups in `/data` means a panic "Factory Reset" destroys your only rescue image. PhoenixBoot stores a primary fast-access backup in `/data/adb/`, but actively hunts for your `/persist` or `/cache` partitions to store a secondary, **factory-reset-safe backup**.
* **Non-Destructive Fail-Safes:** If a backup image SHA256 hash mismatches, PhoenixBoot will *never* automatically delete it. It preserves the corrupt file for human forensic recovery and gracefully exits to recovery mode.
* **GKI 2.0 & Bootconfig Support:** Fully supports Android 12+ GKI devices by natively scanning and patching `vendor_boot` and `init_boot` bootconfig blocks.

---

## 📱 Compatibility

| Root Manager | Supported |
| :--- | :---: |
| KernelSU | ✅ |
| Magisk | ✅ |
| APatch | ✅ |

| Partition Scheme & OS | Supported |
| :--- | :---: |
| A/B (Seamless Updates) | ✅ |
| Legacy A-only | ✅ |
| GKI 2.0 (Android 12+) | ✅ |

**Tested on:** Redmi Note 9 Pro Max (miatoll) · LineageOS · Android 15 · KernelSU

---

## 🚀 Installation

### Requirements
* Rooted device (Magisk, KernelSU, or APatch)
* Custom recovery recommended (TWRP, OrangeFox) but not strictly required for installation.

### Steps
1. Download `PhoenixBoot_v1.2.zip` from the [Releases](https://github.com/Lysine000/PhoenixBoot/releases) page.
2. Open your root manager (Magisk, KernelSU, or APatch).
3. Navigate to the **Modules** tab and select **Install from storage**.
4. Select the zip file.
5. Review the on-screen flashing logs to ensure safety checks passed and your secondary backup was successfully stored in `/persist` or `/cache`.
6. Reboot to system.

> **Note:** The installer performs a pre-flight check on your `/misc` block for proprietary OEM data before writing. If it detects OEM data, it will safely fall back to `/data`-only tracking to completely eliminate the risk of partition corruption.

---

## ⚙️ How It Works

1. **Backup Phase:** Your current boot partition is backed up to `/data/adb/phoenixboot/boot_orig.img`. A secondary copy is mirrored to `/persist/phoenixboot/` (or `/cache`). SHA256 hashes are generated.
2. **Patch Phase:** Existing `panic=` commands are scrubbed, and `panic=5` is injected into the kernel cmdline (or GKI `bootconfig`).
3. **Early-Init Watchdog (Tier 1):** If the kernel panics during early boot, the hardware reboots, and our `boot_abort_handler` instantly increments a persistent counter byte safely hidden at offset `0xD000` in the `/misc` partition.
4. **Runtime Watchdog (Tier 2):** A background service monitors for `sys.boot_completed`. If the device rapid-reboots 5 times, or hangs for 15 minutes, the watchdog intercepts the boot process, verifies the SHA256 hash of your backups, restores the boot partition, and reboots you into recovery.

*Once the device has been completely stable for 5 minutes (300 seconds), all panic counters are automatically reset to zero for the next boot cycle.*

---

## 🔍 Verify Installation & Logs

You can verify PhoenixBoot is actively protecting your device by checking its runtime logs:

1. After a normal boot, wait exactly 5 minutes.
2. Open a Root File Explorer and navigate to `/data/adb/phoenixboot/`.
3. Open `watchdog.log` as text.
4. You should see a log entry stating: `[*] Device stable after 300s. Panic counters reset.`

If you experience a severe bootloop and PhoenixBoot cannot automatically flash the image (e.g., all backups are somehow corrupted), it will generate a `RECOVERY_NEEDED.txt` file in that same folder detailing exactly how to manually restore your device via ADB.

---

## 🆘 Emergency Manual Restore

If you ever need to manually restore your pristine boot image, boot into your custom recovery (TWRP/OrangeFox), open the terminal, and run:

```sh
# Example for standard A/B devices:
dd if=/persist/phoenixboot/boot_orig.img of=/dev/block/by-name/boot_a
# (or boot_b depending on your active slot)
```

---

## 🗑️ Uninstallation

To remove PhoenixBoot, simply uninstall the module from your root manager app (Magisk/KernelSU) and reboot.

During the removal process, PhoenixBoot's `uninstall.sh` script will automatically verify the SHA256 hashes and flawlessly restore your original, unpatched boot image. No manual flashing required.

---

## ❓ FAQ

**What happens if I have a locked bootloader or use AVB (avbroot)?**
Unlike older scripts that will instantly hard brick your locked device, v1.2 features a multi-signal hardware lock detector. If it detects an enforced bootloader lock, it aborts the boot patching process and safely falls back into "Monitor-Only" mode.

**Will this trip SafetyNet/Play Integrity?**
PhoenixBoot modifies the boot image cmdline which may affect boot image hash verification. If you use PlayIntegrityFix or similar modules, they handle this transparently.

**Does this work on GKI (Generic Kernel Image) devices?**
Yes. PhoenixBoot v1.2 natively scans and patches the bootconfig block found inside `vendor_boot` or `init_boot` partitions on modern Android 12+ GKI devices.

**What happens if my backup gets corrupted?**
PhoenixBoot strictly verifies the SHA256 hash of the backup before restoring. If the primary `/data` backup is corrupt, it falls back to the `/persist` backup. If all backups are corrupt, it will NOT flash them. It refuses to delete the corrupt files (leaving them for manual forensic recovery) and gracefully halts to recovery mode.

---

## 💬 Support & Contact

[![Discord](https://img.shields.io/badge/Discord-lysine.__.-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.com/users/1104792474091782175)

**Discord Username:** `lysine.__.`  
**Discord User ID:** `1104792474091782175`

---

## 📝 Changelog

### v1.2 (Current)
* **[ARCH]** Complete rewrite of bootloop detection and backup logic.
* **[NEW]** Multi-signal bootloader lock detection prevents hard bricks on AVB/locked devices.
* **[NEW]** Dual backup system: `/data` + `/persist`/`/cache` (Survives factory resets!).
* **[NEW]** `/misc` persistent hardware counter enables early-boot panic tracking, closing the `panic=5` RAM-clear trap.
* **[NEW]** Pre-flight "Zero-Check" on `/misc` partition to prevent OEM data corruption.
* **[NEW]** Native Magisk/KSU `$BOOTIMAGE` partition detection.
* **[NEW]** GKI 2.0 bootconfig block scanning and `panic=5` injection (`vendor_boot`/`init_boot`).
* **[FIX]** Watchdog never deletes a corrupt backup — logs and fails gracefully to recovery.
* **[FIX]** Dynamic space checks verify actual boot image size before extraction.
* **[FIX]** Unpack validation strictly checks exit codes and component files (kernel, header) before repacking.
* **[FIX]** POSIX-compliant `sed` scrub for existing `panic=N` cmdline tokens.

### v1.0
* Initial public release.
* 15-minute watchdog timer and SHA1 backup integrity.

---

## 🤝 Credits

* Built and tested by the PhoenixBoot team on a real device.
* Powered by [magiskboot](https://github.com/topjohnwu/Magisk).

---

## 📜 License

**GPL-3.0 License** — This project is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation. See the `LICENSE` file for full details.
