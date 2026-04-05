#!/system/bin/sh
# PhoenixBoot v1.3 - Runtime Watchdog
#
# This service runs after /data is decrypted. It checks for bootloops
# by looking at the panic counters in /misc and /data.
#
# Note: mkdir -p is called first because KernelSU can be weird about 
# directory persistence between boots.

PHOENIXBOOT_DIR="/data/adb/phoenixboot"
LOG="$PHOENIXBOOT_DIR/watchdog.log"
CONFIG="$PHOENIXBOOT_DIR/config"

# A bit of thresholding for the loop detection
PANIC_THRESHOLD=3
STABILITY_WINDOW=300
RAPID_BOOT_THRESHOLD=5

# Helpers
_log() {
    # Just a safety check to make sure the dir exists before writing
    [ -d "$PHOENIXBOOT_DIR" ] || mkdir -p "$PHOENIXBOOT_DIR" 2>/dev/null
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG" 2>/dev/null
}

_write_failure_log() {
    # If recovery fails, we leave this note for the user so they aren't stuck
    FAIL_LOG="$PHOENIXBOOT_DIR/RECOVERY_NEEDED.txt"
    {
        echo "=== PhoenixBoot: Recovery Failed ==="
        echo "Time: $(date)"
        echo "Reason: $BOOTLOOP_REASON"
        echo "Partitions: $BOOT_PARTITION (${SLOT_SUFFIX:-A-only})"
        echo "Backup: $PHOENIXBOOT_DIR/boot_orig.img"
        echo ""
        echo "Auto-restore didn't work. You'll need to flash your stock boot.img."
        echo "You can find your build fingerprint in: $PHOENIXBOOT_DIR/config"
        echo ""
        echo "Check $LOG for the full story."
    } > "$FAIL_LOG" 2>/dev/null
    _log "Manual recovery note written to $FAIL_LOG"
}

_reset_misc_counter() {
    if [ "$USE_MISC_COUNTER" = "true" ] && [ -n "$MISC_PARTITION" ] && [ -b "$MISC_PARTITION" ]; then
        printf 'PHNXBT\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' | \
            dd of="$MISC_PARTITION" bs=1 seek="$MISC_OFFSET" count=16 conv=notrunc 2>/dev/null
        _log "/misc panic counter reset to 0."
    fi
}

_read_misc_counter() {
    MISC_PANIC_COUNT=0
    MISC_PANIC_VALID=false
    if [ "$USE_MISC_COUNTER" != "true" ] || [ -z "$MISC_PARTITION" ] || [ ! -b "$MISC_PARTITION" ]; then
        _log "Tier-1 /misc counter not available (USE_MISC_COUNTER=$USE_MISC_COUNTER)."
        return
    fi
    MISC_RAW=$(dd if="$MISC_PARTITION" bs=1 skip="$MISC_OFFSET" count=9 2>/dev/null \
               | od -A n -t x1 | tr -d ' \n')
    MISC_RAW_MAGIC="${MISC_RAW:0:16}"   # first 8 bytes = 16 hex chars
    if [ "$MISC_RAW_MAGIC" = "50484e5842540100" ]; then
        MISC_PANIC_COUNT_HEX="${MISC_RAW:16:2}"
        MISC_PANIC_COUNT=$(printf '%d' "0x${MISC_PANIC_COUNT_HEX}" 2>/dev/null || echo 0)
        MISC_PANIC_VALID=true
        _log "Tier-1 /misc panic counter: $MISC_PANIC_COUNT (valid magic)"
    else
        _log "Tier-1 /misc magic mismatch (got: ${MISC_RAW_MAGIC:-empty}). Counter not trusted."
    fi
}

_do_recovery() {
    _log "!!! BOOTLOOP CONFIRMED. Initiating recovery sequence. !!!"
    _log "Reason: $BOOTLOOP_REASON"

    PRIMARY_BACKUP="$PHOENIXBOOT_DIR/boot_orig.img"
    PRIMARY_SHA_FILE="$PHOENIXBOOT_DIR/boot_orig.sha256"
    EXPECTED_SHA=$(cat "$PRIMARY_SHA_FILE" 2>/dev/null | tr -d '[:space:]')
    RESTORE_SOURCE=""

    # Validate primary backup
    if [ -f "$PRIMARY_BACKUP" ] && [ -n "$EXPECTED_SHA" ]; then
        PRIMARY_ACTUAL_SHA=$(sha256sum "$PRIMARY_BACKUP" | awk '{print $1}')
        if [ "$PRIMARY_ACTUAL_SHA" = "$EXPECTED_SHA" ]; then
            RESTORE_SOURCE="$PRIMARY_BACKUP"
            _log "Primary backup SHA256 OK."
        else
            _log "Primary backup SHA256 MISMATCH — expected=$EXPECTED_SHA got=$PRIMARY_ACTUAL_SHA"
            _log "Primary is corrupt. Trying secondary. NOT deleting corrupt file."
        fi
    else
        _log "Primary backup missing or no SHA256 file. Trying secondary."
    fi

    # Validate secondary backup
    if [ -z "$RESTORE_SOURCE" ] && [ -n "$SECONDARY_BACKUP_PATH" ] && [ -f "$SECONDARY_BACKUP_PATH" ]; then
        SECONDARY_ACTUAL_SHA=$(sha256sum "$SECONDARY_BACKUP_PATH" | awk '{print $1}')
        if [ "$SECONDARY_ACTUAL_SHA" = "$EXPECTED_SHA" ]; then
            RESTORE_SOURCE="$SECONDARY_BACKUP_PATH"
            _log "Secondary backup SHA256 OK. Using /$SECONDARY_LOCATION copy."
            cp "$SECONDARY_BACKUP_PATH" "$PRIMARY_BACKUP" 2>/dev/null && \
                _log "Primary refreshed from secondary." || \
                _log "Could not refresh primary from secondary (non-fatal)."
        else
            _log "Secondary backup SHA256 MISMATCH — expected=$EXPECTED_SHA got=$SECONDARY_ACTUAL_SHA"
        fi
    fi

    if [ -n "$RESTORE_SOURCE" ]; then
        _log "Flashing $RESTORE_SOURCE to $BOOT_PARTITION ..."
        dd if="$RESTORE_SOURCE" of="$BOOT_PARTITION" bs=4096 2>> "$LOG"
        FLASH_EXIT=$?
        if [ $FLASH_EXIT -eq 0 ]; then
            _log "SUCCESS: Original boot image restored."
            echo "0" > "$PHOENIXBOOT_DIR/rapid_boot_count"
            echo "0" > "$PHOENIXBOOT_DIR/panic_count"
            _reset_misc_counter
            _log "Rebooting to recovery for user inspection."
            sleep 3
            reboot recovery
        else
            _log "CRITICAL: Flash failed (exit $FLASH_EXIT). Manual intervention required."
            _write_failure_log
            reboot recovery
        fi
    else
        _log "CRITICAL: ALL backups are corrupt or missing. Cannot auto-restore."
        _write_failure_log
        # Do not reboot — let the device keep running so user can ADB in
    fi
}

# =============================================================================
# SECTION 2: MAIN EXECUTION
# =============================================================================

# ── Step 1: Ensure our data directory exists BEFORE any log write ─────────────
# This is the fix for the "nothing in /data/adb/" symptom. On KernelSU the
# directory is not guaranteed to persist between reboots in the same way as
# Magisk. We create it unconditionally before touching $LOG or $CONFIG.
mkdir -p "$PHOENIXBOOT_DIR" 2>/dev/null
chmod 700 "$PHOENIXBOOT_DIR" 2>/dev/null

_log "=== PhoenixBoot v1.3 Watchdog START ==="
_log "Boot timestamp: $(date +%s)"
_log "Root manager context: $(id 2>/dev/null || echo unknown)"

# ── Step 2: Load config ───────────────────────────────────────────────────────
if [ ! -f "$CONFIG" ]; then
    _log "ERROR: Config not found at $CONFIG."
    _log "This means either:"
    _log "  a) customize.sh did not complete successfully during flash, OR"
    _log "  b) /data was wiped since installation."
    _log "PhoenixBoot cannot protect this boot. Watchdog exiting."
    exit 1
fi
. "$CONFIG"
_log "Config loaded. BOOT_PARTITION=$BOOT_PARTITION IS_AB=$IS_AB"

# ── Step 3: Monitor-only mode (locked bootloader) ────────────────────────────
if [ "$MONITOR_ONLY" = "true" ]; then
    _log "MONITOR-ONLY mode active (locked bootloader declared by user at install time)."
    _log "Boot event logged. No recovery actions will be taken."
    echo "$(date +%s)" >> "$PHOENIXBOOT_DIR/boot_log"
    exit 0
fi

# ── Step 4: Read Tier-1 /misc panic counter ───────────────────────────────────
_read_misc_counter

# ── Step 5: Tier-2 rapid-boot counter ────────────────────────────────────────
DATA_RAPID_BOOTS=0
LAST_BOOT_TS=$(cat "$PHOENIXBOOT_DIR/last_boot_ts" 2>/dev/null || echo 0)
NOW=$(date +%s)
ELAPSED_SINCE_LAST=$(( NOW - LAST_BOOT_TS ))

if [ "$ELAPSED_SINCE_LAST" -lt 90 ] && [ "$LAST_BOOT_TS" -gt 0 ]; then
    DATA_RAPID_BOOTS=$(cat "$PHOENIXBOOT_DIR/rapid_boot_count" 2>/dev/null || echo 0)
    DATA_RAPID_BOOTS=$(( DATA_RAPID_BOOTS + 1 ))
    echo "$DATA_RAPID_BOOTS" > "$PHOENIXBOOT_DIR/rapid_boot_count"
    _log "Rapid boot: elapsed=${ELAPSED_SINCE_LAST}s count=$DATA_RAPID_BOOTS"
else
    echo "0" > "$PHOENIXBOOT_DIR/rapid_boot_count"
    DATA_RAPID_BOOTS=0
    _log "Normal boot interval: elapsed=${ELAPSED_SINCE_LAST}s. Rapid counter reset."
fi
echo "$NOW" > "$PHOENIXBOOT_DIR/last_boot_ts"

# ── Step 6: Bootloop decision ─────────────────────────────────────────────────
BOOTLOOP_DETECTED=false
BOOTLOOP_REASON=""

if $MISC_PANIC_VALID && [ "$MISC_PANIC_COUNT" -ge "$PANIC_THRESHOLD" ]; then
    BOOTLOOP_DETECTED=true
    BOOTLOOP_REASON="Tier-1: misc counter=$MISC_PANIC_COUNT >= threshold=$PANIC_THRESHOLD"
fi

if [ "$DATA_RAPID_BOOTS" -ge "$RAPID_BOOT_THRESHOLD" ]; then
    BOOTLOOP_DETECTED=true
    BOOTLOOP_REASON="Tier-2: rapid boots=$DATA_RAPID_BOOTS >= threshold=$RAPID_BOOT_THRESHOLD"
fi

_log "Bootloop check: detected=$BOOTLOOP_DETECTED reason='$BOOTLOOP_REASON'"

# ── Step 7: Act ───────────────────────────────────────────────────────────────
if $BOOTLOOP_DETECTED; then
    _do_recovery
    exit 0
fi

# ── Step 8: Normal boot — background stability timer ─────────────────────────
_log "Normal boot confirmed. Starting ${STABILITY_WINDOW_SECONDS}s stability monitor..."

(
    sleep "$STABILITY_WINDOW_SECONDS"
    echo "$(date +%s)" > "$PHOENIXBOOT_DIR/last_good_boot"
    echo "0" > "$PHOENIXBOOT_DIR/rapid_boot_count"
    _reset_misc_counter
    _log "Stability window passed. Device marked stable. Panic counters reset."
) &

_log "Stability monitor launched in background (PID=$!)."
_log "=== PhoenixBoot Watchdog COMPLETE (normal path) ==="
exit 0
