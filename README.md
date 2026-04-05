# PhoenixBoot v1.3

Universal bootloop protection for rooted Android. Patches your boot image with `panic=5`, monitors for crash cycles via a two-tier watchdog, and auto-restores a verified backup if things go sideways.

---

## Compatibility & Warnings

- **Requires Unlocked Bootloader:** If your bootloader is locked, do not flash this. The module will detect the lock and default to "Monitor-only" mode, but it's better to just not risk it.
- **Samsung / Knox:** Samsung devices are tricky. Flashing any modified boot image **will** trip your Knox eFuse permanently. Also, some Samsung devices use non-standard `/misc` offsets. If you're on a Samsung, check your config after install and maybe set `USE_MISC_COUNTER=false` if you're worried about OEM data at `0xD000`.
- **MediaTek (MTK):** Some MTK devices have weird partition paths. If the installer can't find your boot partition, it will abort. Check the logs.

---

## How It Works (The Technical Bit)

### 1. The Boot Patch (Early Panic)
The installer uses `magiskboot` to inject `panic=5` into your kernel command line or `bootconfig` block (for GKI 2.0). This ensures the kernel reboots instead of hanging on a black screen when a panic occurs. 

### 2. Tier-1 Watchdog: `/misc` Counter
We use a small 16-byte block at offset `0xD000` in the `/misc` partition.
- **Magic:** `PHNXBT` (0x50484e584254)
- **Offset:** `0xD000` (Safe on AOSP/Pixel, use caution on Samsung/MTK).
A service runs at `early-init` to increment this counter before `/data` is even mounted. If it hits 3, we declare a loop.

### 3. Tier-2 Watchdog: Rapid Reboot Tracking
If the phone boots and crashes within 90 seconds, a counter in `/data/adb/phoenixboot/` is incremented. If this hits 5, we initiate recovery. 

### 4. Verified Recovery
If a loop is confirmed, the watchdog:
1. Verifies the SHA256 of the backup at `/data/adb/phoenixboot/boot_orig.img`.
2. Checks fallback locations in `/persist/` or `/cache/` if the primary is missing.
3. Flashes the stock boot image and reboots you to recovery.

---

## Manual Recovery

If the auto-recovery fails, look for `RECOVERY_NEEDED.txt` in your PhoenixBoot data folder. You can always get back to stock by flashing the `boot_orig.img` we created during install:

```bash
# Example for A/B devices via ADB shell in recovery:
dd if=/data/adb/phoenixboot/boot_orig.img of=/dev/block/by-name/boot_a
```

---

## Build from Source
I've included a `build.sh` script to make it easy to package the module yourself.
```bash
chmod +x build.sh
./build.sh
```

---

## Changelog
- **v1.3:** Removed spoofable bootloader auto-detection; now uses a manual Volume Key prompt at install. Fixed KernelSU directory persistence issues. Added GKI 2.0 `bootconfig` patching support.
- **v1.2:** Introduced the dual-backup system and `/misc` early-panic counter.

--
*Lysine000*
