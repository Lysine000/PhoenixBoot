# Phoenix Boot Changelog

## v1.5
- **Hardware Panic Button:** Tap Volume Down 5 times during boot to force an immediate partition restore.
- **Panic Persistence:** Trigger count survives hard kernel panics (stored in `/data/local/tmp/`).
- **Auto-Kill Switch:** Panic listener automatically stops once boot is completed to prevent accidental triggers.

## v1.4
- **Manual Rescue Trigger:** Hold Volume Up during the stability window to force a recovery.
- **Improved Watchdog:** Fixed a critical bug where the stability timer was not waiting for the full window.
- **User-Friendly Backups:** Original boot image is now automatically exported to `/sdcard/PhoenixBoot_Backup/` during install.
- **phnxbt CLI:** New diagnostic tool to check protection status from the terminal.
- **Enhanced Compatibility:** Better support for minimal recovery environments and GKI 2.0 devices.

## v1.3
- Dual-tier watchdog (Tier-1: /misc, Tier-2: /data)
- Automatic restoration of verified boot image backups
- GKI 2.0 / bootconfig support
- Manual volume-key verification for bootloader status
- Support for Magisk, KernelSU, and APatch
