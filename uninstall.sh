#!/system/bin/sh
PHOENIXBOOT_DIR="/data/adb/phoenixboot"
LOG="$PHOENIXBOOT_DIR/uninstall.log"
CONFIG="$PHOENIXBOOT_DIR/config"

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"; }

_log "=== PhoenixBoot v1.2 Uninstall ==="

if [ ! -f "$CONFIG" ]; then
    _log "Config not found. Cannot locate boot partition or backups."
    _log "Please manually flash your original boot image."
    exit 1
fi

. "$CONFIG"

PRIMARY_BACKUP="$PHOENIXBOOT_DIR/boot_orig.img"
EXPECTED_SHA=$(cat "$PHOENIXBOOT_DIR/boot_orig.sha256" 2>/dev/null | tr -d '[:space:]')
RESTORE_SOURCE=""

if [ -f "$PRIMARY_BACKUP" ] && [ -n "$EXPECTED_SHA" ]; then
    ACTUAL_SHA=$(sha256sum "$PRIMARY_BACKUP" | awk '{print $1}')
    if [ "$ACTUAL_SHA" = "$EXPECTED_SHA" ]; then
        RESTORE_SOURCE="$PRIMARY_BACKUP"
        _log "Using primary backup (SHA256 verified)."
    else
        _log "Primary backup SHA256 mismatch. Trying secondary."
    fi
fi

if [ -z "$RESTORE_SOURCE" ] && [ -n "$SECONDARY_BACKUP_PATH" ] && [ -f "$SECONDARY_BACKUP_PATH" ]; then
    ACTUAL_SHA=$(sha256sum "$SECONDARY_BACKUP_PATH" | awk '{print $1}')
    [ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] && {
        RESTORE_SOURCE="$SECONDARY_BACKUP_PATH"
        _log "Using secondary backup from /$SECONDARY_LOCATION (SHA256 verified)."
    }
fi

if [ -z "$RESTORE_SOURCE" ]; then
    _log "ERROR: No valid backup found. Cannot auto-restore."
    _log "Please flash your stock boot.img manually."
    exit 1
fi

_log "Restoring original boot image to $BOOT_PARTITION..."
dd if="$RESTORE_SOURCE" of="$BOOT_PARTITION" bs=4096 2>> "$LOG"
if [ $? -eq 0 ]; then
    _log "Original boot image restored successfully."
    if [ "$USE_MISC_COUNTER" = "true" ] && [ -n "$MISC_PARTITION" ] && [ -b "$MISC_PARTITION" ]; then
        printf 'PHNXBT\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' | \
            dd of="$MISC_PARTITION" bs=1 seek="$MISC_OFFSET" count=16 conv=notrunc 2>/dev/null
        _log "/misc panic counter cleared."
    fi
    _log "Uninstall complete. Reboot to apply."
else
    _log "ERROR: Flash failed. Boot partition may be in an undefined state."
    _log "Please manually flash boot_orig.img from $PHOENIXBOOT_DIR"
    exit 1
fi
