#!/sbin/sh
# PhoenixBoot v1.3 - Installer
# Author: Lysine000
#
# Universal bootloop protection for Android.
# This script handles the installation, patching, and backup of the boot image.
# We skipunzip is not set because we need the module files in $MODPATH.

ui_print " "
ui_print "-----------------------------"
ui_print " PhoenixBoot v1.3 Installer "
ui_print "-----------------------------"
ui_print " "

# Standard abort helper with some cleanup
abort_install() {
    ui_print " "
    ui_print "[!] ERROR: $1"
    ui_print "    Installation aborted. No changes made."
    ui_print " "
    [ -n "$SESSION_TMP" ] && rm -rf "$SESSION_TMP"
    exit 1
}

# Just some simple logging helpers to keep the output clean
log_info() { ui_print "[*] $1"; }
log_ok()   { ui_print "[+] $1"; }
log_warn() { ui_print "[W] $1"; }

# For when we can't (or shouldn't) patch the boot partition
_deploy_monitor_only_mode() {
    ui_print "[*] Entering MONITOR-ONLY mode (no patching/flashing)."
    ui_print "    Watchdog will still log boot events, but auto-recovery is disabled."
    mkdir -p "$MODPATH"
    mkdir -p "/data/adb/phoenixboot"
    echo "MONITOR_ONLY=true" > /data/adb/phoenixboot/config
    chmod 755 "$MODPATH/service.sh"
}

log_info "Probing environment..."

# Check which root manager we're dealing with
ROOT_MANAGER="unknown"
if [ -n "$MAGISK_VER_CODE" ]; then
    ROOT_MANAGER="magisk"
elif [ -d /data/adb/ksud ] || [ -f /data/adb/ksu/ksu.ko ]; then
    ROOT_MANAGER="kernelsu"
elif [ -d /data/adb/apatch ]; then
    ROOT_MANAGER="apatch"
fi
log_info "Detected root manager: $ROOT_MANAGER"

# Figure out the partition layout (A/B or A-only)
SLOT_SUFFIX=$(getprop ro.boot.slot_suffix 2>/dev/null)
IS_AB=false
if [ -n "$SLOT_SUFFIX" ]; then
    IS_AB=true
    log_info "A/B device detected (active slot: $SLOT_SUFFIX)"
else
    log_info "Standard A-only layout detected."
fi

# Bootloader status check
# We don't trust auto-detection anymore (too easy to spoof in recovery),
# so we ask the user directly via volume keys.
STATE_FILE=/data/local/tmp/phoenix_boot_state
rm -f "$STATE_FILE" 2>/dev/null

ui_print " "
ui_print "[?] Is your bootloader UNLOCKED?"
ui_print "    Patching a locked bootloader is a one-way ticket to a hard brick."
ui_print "    Please use Volume Up for UNLOCKED or Volume Down for LOCKED."
ui_print " "

sh "$MODPATH/ask_bootloader.sh"

BOOT_LOCKED=false
if [ -f "$STATE_FILE" ]; then
    USER_STATE=$(cat "$STATE_FILE" | tr -d '[:space:]')
    case "$USER_STATE" in
        locked)
            BOOT_LOCKED=true
            log_info "User declared: LOCKED"
            ;;
        unlocked)
            BOOT_LOCKED=false
            log_ok "User declared: UNLOCKED"
            ;;
        *)
            BOOT_LOCKED=true
            log_warn "Unknown input '$USER_STATE' - defaulting to LOCKED for safety."
            ;;
    esac
else
    BOOT_LOCKED=true
    log_warn "Could not read bootloader state (input script error). Defaulting to LOCKED."
fi

rm -f "$STATE_FILE" 2>/dev/null

if $BOOT_LOCKED; then
    ui_print " "
    ui_print "[!] BOOTLOADER IS LOCKED"
    ui_print "    Skipping boot image patch to prevent a brick."
    ui_print "    The module will still install in monitor-only mode."
    ui_print " "
    _deploy_monitor_only_mode
    exit 0
fi

log_ok "Unlocked bootloader confirmed. Proceeding with the full install."

log_info "Locating boot partition..."

BOOT_PARTITION=""

if [ -n "$BOOTIMAGE" ] && [ -b "$BOOTIMAGE" ]; then
    BOOT_PARTITION="$BOOTIMAGE"
    log_ok "Boot partition from root manager: $BOOT_PARTITION"
else
    log_warn "\$BOOTIMAGE not set or not a block device (value: '${BOOTIMAGE:-<empty>}')."
    log_warn "Falling back to manual partition search..."

    _find_partition_fallback() {
        if $IS_AB; then _sfx="$SLOT_SUFFIX"; else _sfx=""; fi
        for _base in \
            "/dev/block/bootdevice/by-name/boot${_sfx}" \
            "/dev/block/by-name/boot${_sfx}"
        do
            [ -b "$_base" ] && { echo "$_base"; return 0; }
        done
        for _resolved in /dev/block/platform/*/by-name/boot${_sfx}; do
            [ -b "$_resolved" ] && { echo "$_resolved"; return 0; }
        done
        return 1
    }

    BOOT_PARTITION=$(_find_partition_fallback)
    [ -z "$BOOT_PARTITION" ] && \
        abort_install "Cannot locate boot partition. \$BOOTIMAGE was empty and fallback search failed."
    log_ok "Boot partition (fallback): $BOOT_PARTITION"
fi

log_info "Measuring boot partition size..."

BOOT_IMG_SIZE=$(blockdev --getsize64 "$BOOT_PARTITION" 2>/dev/null)
if [ -z "$BOOT_IMG_SIZE" ] || [ "$BOOT_IMG_SIZE" -eq 0 ]; then
    BOOT_IMG_SIZE=$(stat -c '%s' "$BOOT_PARTITION" 2>/dev/null || echo 0)
fi
[ "$BOOT_IMG_SIZE" -eq 0 ] && abort_install "Cannot determine boot image size."

BOOT_IMG_SIZE_MB=$(( BOOT_IMG_SIZE / 1048576 ))
log_info "Boot image size: ${BOOT_IMG_SIZE_MB}MB (${BOOT_IMG_SIZE} bytes)"

REQUIRED_BYTES=$(( BOOT_IMG_SIZE * 3 + 10485760 ))
REQUIRED_MB=$(( REQUIRED_BYTES / 1048576 ))

DATA_AVAIL=$(df -k /data 2>/dev/null | awk 'NR==2{print $4}')
DATA_AVAIL_BYTES=$(( ${DATA_AVAIL:-0} * 1024 ))

log_info "Required: ${REQUIRED_MB}MB  Available on /data: $(( DATA_AVAIL_BYTES / 1048576 ))MB"
[ "$DATA_AVAIL_BYTES" -lt "$REQUIRED_BYTES" ] && \
    abort_install "Insufficient space on /data (need ${REQUIRED_MB}MB, have $(( DATA_AVAIL_BYTES / 1048576 ))MB)."

log_ok "Space check passed."

SESSION_TMP=$(mktemp -d /data/adb/phoenixboot_install_XXXXXX)
[ -d "$SESSION_TMP" ] || abort_install "Cannot create secure temp directory."
chmod 700 "$SESSION_TMP"
log_info "Session workspace: $SESSION_TMP"

log_info "Reading boot image from partition..."
WORK_IMG="$SESSION_TMP/boot_work.img"
ORIG_IMG="$SESSION_TMP/boot_orig.img"

MIN_VALID_BYTES=1048576

log_info "Attempt 1: dd (block-aligned read)..."
dd if="$BOOT_PARTITION" of="$ORIG_IMG" bs=4096 2>/dev/null
DD_EXIT=$?
ORIG_IMG_SIZE=$(stat -c '%s' "$ORIG_IMG" 2>/dev/null || echo 0)

if [ "$DD_EXIT" -ne 0 ] || [ "$ORIG_IMG_SIZE" -lt "$MIN_VALID_BYTES" ]; then
    log_warn "dd read suspicious: exit=$DD_EXIT size=${ORIG_IMG_SIZE}B (expected >=${MIN_VALID_BYTES}B)."
    log_warn "Attempt 2: falling back to cat (byte-stream read)..."
    rm -f "$ORIG_IMG"
    cat "$BOOT_PARTITION" > "$ORIG_IMG" 2>/dev/null
    ORIG_IMG_SIZE=$(stat -c '%s' "$ORIG_IMG" 2>/dev/null || echo 0)

    if [ "$ORIG_IMG_SIZE" -lt "$MIN_VALID_BYTES" ]; then
        abort_install "Failed to read boot partition: extracted file is empty (size=${ORIG_IMG_SIZE}B after both dd and cat attempts). Check that $BOOT_PARTITION is accessible and not remounted read-only."
    fi
    log_ok "cat fallback succeeded. Image size: ${ORIG_IMG_SIZE}B."
else
    log_ok "dd read succeeded. Image size: ${ORIG_IMG_SIZE}B."
fi

ORIG_SHA256=$(sha256sum "$ORIG_IMG" | awk '{print $1}')
log_info "Boot image SHA256: $ORIG_SHA256"

MAGIC=$(xxd -l 8 "$ORIG_IMG" | awk '{print $2$3}')
case "$MAGIC" in
    414e4452|41524452|544f5354) log_ok "Boot image magic validated." ;;
    *) log_warn "Unexpected boot magic: $MAGIC. Proceeding with caution." ;;
esac

cp "$ORIG_IMG" "$WORK_IMG"

log_info "Unpacking boot image..."

# magiskboot always writes output files (header, kernel, ramdisk.cpio, …)
# into the current working directory. cd into SESSION_TMP so those files
# land right beside WORK_IMG, which is also in SESSION_TMP.
UNPACK_DIR="$SESSION_TMP"
cd "$SESSION_TMP" || abort_install "Cannot enter session directory."

magiskboot unpack "$WORK_IMG" > "$SESSION_TMP/unpack.log" 2>&1
UNPACK_EXIT=$?

[ $UNPACK_EXIT -ne 0 ] && {
    log_warn "magiskboot unpack exit code: $UNPACK_EXIT"
    cat "$SESSION_TMP/unpack.log" | while read line; do log_warn "  $line"; done
    abort_install "magiskboot failed to unpack boot image. Image may be GKI 2.0 or encrypted."
}

# GKI 2.0 workaround: some magiskboot versions exit 0 but write no header
# because the image uses a format they silently skip. Retry with -h (newer
# magiskboot header-only flag), then fall back to extracting the header
# field directly from the raw boot image binary with magiskboot hexpatch
# awareness — or synthesise a minimal header so the cmdline patch can proceed.
if [ ! -f "$UNPACK_DIR/header" ]; then
    log_warn "magiskboot unpack exited 0 but wrote no header (GKI 2.0 / vendor-signed image)."
    log_warn "Attempting retry with -h flag (newer magiskboot)..."

    rm -f "$UNPACK_DIR"/header "$UNPACK_DIR"/kernel "$UNPACK_DIR"/ramdisk.cpio 2>/dev/null
    magiskboot unpack -h "$WORK_IMG" > "$SESSION_TMP/unpack2.log" 2>&1
    UNPACK2_EXIT=$?

    if [ $UNPACK2_EXIT -ne 0 ] || [ ! -f "$UNPACK_DIR/header" ]; then
        log_warn "Retry with -h also produced no header (exit=$UNPACK2_EXIT)."
        log_warn "Falling back to bootconfig-only patch path (no kernel cmdline edit)."
        log_warn "The panic=5 parameter will be injected via bootconfig block only."

        # Synthesise a minimal header with an empty cmdline so the rest of
        # the script (bootconfig path) can run and the repack step is skipped.
        # We mark the header as synthetic so the repack block can detect it.
        printf 'cmdline=\nSYNTHETIC_HEADER=true\n' > "$UNPACK_DIR/header"
        SYNTHETIC_HEADER=true
    else
        log_ok "Retry with -h succeeded — header extracted."
        SYNTHETIC_HEADER=false
    fi
else
    SYNTHETIC_HEADER=false
fi

[ ! -f "$UNPACK_DIR/kernel" ] && [ "$SYNTHETIC_HEADER" != "true" ] && \
    abort_install "Unpack produced no kernel. Cannot safely patch."
[ ! -f "$UNPACK_DIR/ramdisk.cpio" ] && log_warn "No ramdisk.cpio found (GKI 2.0 image — this is expected)."

if [ "$SYNTHETIC_HEADER" = "true" ]; then
    log_warn "Running in bootconfig-only mode. Kernel cmdline header edit will be skipped."
    log_warn "Boot image will NOT be repacked/reflashed — only bootconfig block will be patched."
    log_ok "Boot image analysis complete (bootconfig-only mode)."
else
    log_ok "Boot image unpacked and validated."
fi

if [ "$SYNTHETIC_HEADER" != "true" ]; then
    log_info "Patching kernel command line..."

    HEADER_FILE="$UNPACK_DIR/header"
    CURRENT_CMDLINE=$(grep '^cmdline=' "$HEADER_FILE" | sed 's/^cmdline=//')
    log_info "Current cmdline: $CURRENT_CMDLINE"

    SENTINEL=" ${CURRENT_CMDLINE} "
    CLEANED_SENTINEL="$SENTINEL"
    while true; do
        NEXT=$(printf '%s' "$CLEANED_SENTINEL" | sed 's/ panic=[-0-9]*/ /g')
        [ "$NEXT" = "$CLEANED_SENTINEL" ] && break
        CLEANED_SENTINEL="$NEXT"
    done

    CLEANED_CMDLINE=$(printf '%s' "$CLEANED_SENTINEL" | tr -s ' ' | sed 's/^ //;s/ $//')
    NEW_CMDLINE="${CLEANED_CMDLINE} panic=5"
    NEW_CMDLINE=$(printf '%s' "$NEW_CMDLINE" | tr -s ' ' | sed 's/^ //')

    log_info "Cleaned cmdline: $CLEANED_CMDLINE"
    log_info "New cmdline:     $NEW_CMDLINE"

    HEADER_TMP="${HEADER_FILE}.tmp"
    sed "s|^cmdline=.*|cmdline=${NEW_CMDLINE}|" "$HEADER_FILE" > "$HEADER_TMP" && \
        mv "$HEADER_TMP" "$HEADER_FILE" || \
        abort_install "Failed to write patched cmdline back to header."
else
    log_warn "Skipping kernel cmdline patch (bootconfig-only mode — no unpacked header)."
fi

log_info "Checking for GKI bootconfig block..."

HAS_BOOTCONFIG_CMD=false
magiskboot bootconfig "$WORK_IMG" >/dev/null 2>&1 && HAS_BOOTCONFIG_CMD=true || true
BOOTCONFIG_TEST_OUT=$(magiskboot bootconfig "$WORK_IMG" 2>&1 || true)
case "$BOOTCONFIG_TEST_OUT" in
    *"unknown"*|*"Usage"*|*"invalid"*)
        HAS_BOOTCONFIG_CMD=false
        log_warn "magiskboot bootconfig subcommand not available (older Magisk/KSU/APatch)."
        log_warn "Skipping bootconfig injection. Header cmdline patch applies only."
        ;;
    "")
        HAS_BOOTCONFIG_CMD=true
        log_info "No bootconfig block in boot image (non-GKI or GKI 1.0 device)."
        ;;
    *)
        HAS_BOOTCONFIG_CMD=true
        log_info "Bootconfig block detected in boot image (GKI 2.0 device)."
        ;;
esac

if $HAS_BOOTCONFIG_CMD && [ -n "$BOOTCONFIG_TEST_OUT" ]; then
    log_info "Patching bootconfig panic= parameter..."

    BOOTCONFIG_FILE="$SESSION_TMP/bootconfig.txt"
    magiskboot bootconfig "$WORK_IMG" > "$BOOTCONFIG_FILE" 2>/dev/null

    if [ -s "$BOOTCONFIG_FILE" ]; then
        BOOTCONFIG_TMP="$SESSION_TMP/bootconfig_patched.txt"

        grep -v '^ *androidboot\.panic *=' "$BOOTCONFIG_FILE" | \
            grep -v '^ *panic *=' > "$BOOTCONFIG_TMP" || true

        printf '\nandroidboot.panic = 5\n' >> "$BOOTCONFIG_TMP"

        magiskboot bootconfig "$WORK_IMG" "$BOOTCONFIG_TMP" > "$SESSION_TMP/bootconfig_write.log" 2>&1
        BOOTCONFIG_WRITE_EXIT=$?

        if [ $BOOTCONFIG_WRITE_EXIT -eq 0 ]; then
            log_ok "Bootconfig panic=5 injected successfully."
        else
            log_warn "Bootconfig write failed (exit $BOOTCONFIG_WRITE_EXIT)."
            log_warn "Proceeding with header cmdline patch only."
        fi
    else
        log_info "Bootconfig file was empty after extraction. Nothing to patch."
    fi

    for VB_NAME in vendor_boot init_boot; do
        VB_PART=""
        if $IS_AB; then _VB_SFX="$SLOT_SUFFIX"; else _VB_SFX=""; fi
        for _vc in \
            "/dev/block/bootdevice/by-name/${VB_NAME}${_VB_SFX}" \
            "/dev/block/by-name/${VB_NAME}${_VB_SFX}"
        do
            [ -b "$_vc" ] && { VB_PART="$_vc"; break; }
        done
        for _vc in /dev/block/platform/*/by-name/${VB_NAME}${_VB_SFX}; do
            [ -b "$_vc" ] && { VB_PART="$_vc"; break; }
        done

        if [ -n "$VB_PART" ]; then
            log_info "Found /${VB_NAME} partition at $VB_PART. Checking for bootconfig..."
            VB_IMG="$SESSION_TMP/${VB_NAME}.img"
            dd if="$VB_PART" of="$VB_IMG" bs=4096 2>/dev/null

            VB_BOOTCONFIG=$(magiskboot bootconfig "$VB_IMG" 2>/dev/null || true)
            if [ -n "$VB_BOOTCONFIG" ]; then
                log_info "Bootconfig found in $VB_NAME. Patching..."
                VB_BC_FILE="$SESSION_TMP/${VB_NAME}_bootconfig.txt"
                VB_BC_TMP="$SESSION_TMP/${VB_NAME}_bootconfig_patched.txt"
                printf '%s\n' "$VB_BOOTCONFIG" > "$VB_BC_FILE"

                grep -v '^ *androidboot\.panic *=' "$VB_BC_FILE" | \
                    grep -v '^ *panic *=' > "$VB_BC_TMP" || true
                printf '\nandroidboot.panic = 5\n' >> "$VB_BC_TMP"

                VB_IMG_PATCHED="$SESSION_TMP/${VB_NAME}_patched.img"
                cp "$VB_IMG" "$VB_IMG_PATCHED"
                if magiskboot bootconfig "$VB_IMG_PATCHED" "$VB_BC_TMP" >/dev/null 2>&1; then
                    VB_UNPACK_DIR="$SESSION_TMP/${VB_NAME}_unpack"
                    mkdir -p "$VB_UNPACK_DIR"
                    VB_REPACKED="$SESSION_TMP/${VB_NAME}_repacked.img"
                    (
                        cd "$VB_UNPACK_DIR" || exit 1
                        magiskboot unpack "$VB_IMG_PATCHED" >/dev/null 2>&1 || exit 1
                        magiskboot repack "$VB_IMG_PATCHED" "$VB_REPACKED" >/dev/null 2>&1 || exit 1
                    )
                    if [ -f "$VB_REPACKED" ]; then
                        log_warn "About to flash patched $VB_NAME — DO NOT interrupt power."
                        dd if="$VB_REPACKED" of="$VB_PART" bs=4096 2>/dev/null && \
                            log_ok "$VB_NAME bootconfig patched and flashed." || \
                            log_warn "$VB_NAME flash failed (non-fatal — header cmdline still active)."
                    else
                        log_warn "$VB_NAME repack failed — skipping flash (non-fatal)."
                    fi
                else
                    log_warn "$VB_NAME bootconfig write failed (non-fatal)."
                fi
            else
                log_info "No bootconfig in $VB_NAME (or not a GKI vendor_boot image)."
            fi
        fi
    done
fi

PATCHED_IMG="$SESSION_TMP/boot_patched.img"
PATCHED_SHA256=""

if [ "$SYNTHETIC_HEADER" != "true" ]; then
    log_info "Repacking boot image..."

    cd "$SESSION_TMP" || abort_install "Cannot re-enter session directory."
    magiskboot repack "$WORK_IMG" "$PATCHED_IMG" > "$SESSION_TMP/repack.log" 2>&1
    REPACK_EXIT=$?

    [ $REPACK_EXIT -ne 0 ] && {
        log_warn "magiskboot repack exit: $REPACK_EXIT"
        abort_install "Repack failed. Original boot image is untouched."
    }

    [ ! -f "$PATCHED_IMG" ] && abort_install "Patched image not generated."

    PATCHED_SIZE=$(stat -c '%s' "$PATCHED_IMG")
    [ "$PATCHED_SIZE" -lt 1048576 ] && abort_install "Patched image is suspiciously small (${PATCHED_SIZE} bytes)."

    PATCHED_SHA256=$(sha256sum "$PATCHED_IMG" | awk '{print $1}')
    log_ok "Patched image ready. SHA256: $PATCHED_SHA256"
else
    log_warn "Skipping repack/flash (bootconfig-only mode — boot image not modified)."
    log_warn "The panic=5 parameter was injected via bootconfig block only."
    PATCHED_SHA256="N/A (bootconfig-only mode)"
fi

log_info "Storing boot image backups..."

PHOENIXBOOT_DATA_DIR="/data/adb/phoenixboot"
mkdir -p "$PHOENIXBOOT_DATA_DIR"
chmod 700 "$PHOENIXBOOT_DATA_DIR"

cp "$ORIG_IMG" "$PHOENIXBOOT_DATA_DIR/boot_orig.img"
echo "$ORIG_SHA256" > "$PHOENIXBOOT_DATA_DIR/boot_orig.sha256"
log_ok "Primary backup stored: $PHOENIXBOOT_DATA_DIR/boot_orig.img"

SECONDARY_BACKUP_PATH=""
SECONDARY_LOCATION="none"

if mount | grep -q ' /persist '; then
    PERSIST_AVAIL=$(df -k /persist 2>/dev/null | awk 'NR==2{print $4}')
    PERSIST_AVAIL_BYTES=$(( ${PERSIST_AVAIL:-0} * 1024 ))
    if [ "$PERSIST_AVAIL_BYTES" -gt "$BOOT_IMG_SIZE" ]; then
        mkdir -p /persist/phoenixboot 2>/dev/null
        if cp "$ORIG_IMG" /persist/phoenixboot/boot_orig.img 2>/dev/null; then
            echo "$ORIG_SHA256" > /persist/phoenixboot/boot_orig.sha256
            SECONDARY_BACKUP_PATH="/persist/phoenixboot/boot_orig.img"
            SECONDARY_LOCATION="persist"
            log_ok "Secondary backup stored: /persist/phoenixboot/boot_orig.img (FACTORY-RESET SAFE)"
        fi
    fi
fi

if [ -z "$SECONDARY_BACKUP_PATH" ] && mount | grep -q ' /cache '; then
    CACHE_AVAIL=$(df -k /cache 2>/dev/null | awk 'NR==2{print $4}')
    CACHE_AVAIL_BYTES=$(( ${CACHE_AVAIL:-0} * 1024 ))
    if [ "$CACHE_AVAIL_BYTES" -gt "$BOOT_IMG_SIZE" ]; then
        mkdir -p /cache/phoenixboot 2>/dev/null
        if cp "$ORIG_IMG" /cache/phoenixboot/boot_orig.img 2>/dev/null; then
            echo "$ORIG_SHA256" > /cache/phoenixboot/boot_orig.sha256
            SECONDARY_BACKUP_PATH="/cache/phoenixboot/boot_orig.img"
            SECONDARY_LOCATION="cache"
            log_ok "Secondary backup stored: /cache/phoenixboot/boot_orig.img"
            log_warn "NOTE: /cache CAN be wiped by factory reset on some devices."
            log_warn "      /persist was unavailable. This backup is a best-effort safety net."
        fi
    fi
fi

if [ -z "$SECONDARY_BACKUP_PATH" ]; then
    log_warn "WARNING: No secondary backup location available (/persist and /cache both unavailable)."
    log_warn "         Primary backup at $PHOENIXBOOT_DATA_DIR/boot_orig.img is your only copy."
    log_warn "         A factory reset WILL destroy it. Export a copy via ADB before resetting."
fi

MISC_PARTITION=""
for cand in /dev/block/bootdevice/by-name/misc /dev/block/by-name/misc; do
    [ -b "$cand" ] && { MISC_PARTITION="$cand"; break; }
done
[ -z "$MISC_PARTITION" ] && for resolved in /dev/block/platform/*/by-name/misc; do
    [ -b "$resolved" ] && { MISC_PARTITION="$resolved"; break; }
done

MISC_OFFSET=53248
USE_MISC_COUNTER=false

if [ -n "$MISC_PARTITION" ]; then
    log_info "Found /misc at: $MISC_PARTITION"
    log_info "Pre-flight check: reading 16 bytes at offset 0x$(printf '%X' $MISC_OFFSET)..."

    PREFLIGHT_HEX=$(dd if="$MISC_PARTITION" bs=1 skip="$MISC_OFFSET" count=16 2>/dev/null \
                    | od -A n -t x1 | tr -d ' \n')

    ALL_ZERO_HEX="00000000000000000000000000000000"
    OUR_MAGIC_PREFIX="50484e5842540100"

    MISC_SAFE_TO_WRITE=false
    if [ "$PREFLIGHT_HEX" = "$ALL_ZERO_HEX" ]; then
        MISC_SAFE_TO_WRITE=true
        log_info "/misc offset is all-zeroes. Safe to initialise."
    elif echo "$PREFLIGHT_HEX" | grep -q "^${OUR_MAGIC_PREFIX}"; then
        MISC_SAFE_TO_WRITE=true
        log_info "/misc offset already contains PhoenixBoot magic. Safe to re-initialise."
    else
        log_warn "/misc offset 0x$(printf '%X' $MISC_OFFSET) contains non-zero OEM data:"
        log_warn "  Raw hex: $PREFLIGHT_HEX"
        log_warn "  Skipping /misc write to avoid OEM data corruption."
        log_warn "  Falling back to /data-only panic counter."
    fi

    if $MISC_SAFE_TO_WRITE; then
        log_info "Writing PhoenixBoot counter magic to /misc..."
        printf 'PHNXBT\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' | \
            dd of="$MISC_PARTITION" bs=1 seek="$MISC_OFFSET" count=16 conv=notrunc 2>/dev/null
        WRITE_EXIT=$?

        if [ $WRITE_EXIT -eq 0 ]; then
            READBACK_HEX=$(dd if="$MISC_PARTITION" bs=1 skip="$MISC_OFFSET" count=6 2>/dev/null \
                           | od -A n -t x1 | tr -d ' \n')
            if [ "$READBACK_HEX" = "50484e584254" ]; then
                USE_MISC_COUNTER=true
                log_ok "/misc panic counter initialised and read-back verified."
            else
                log_warn "/misc read-back mismatch (got: $READBACK_HEX). Falling back to /data counter."
            fi
        else
            log_warn "/misc write failed (exit $WRITE_EXIT). Falling back to /data counter."
        fi
    fi
else
    log_warn "/misc partition not found. Using /data-only panic counter."
    log_warn "Early boot panics (before /data mounts) will NOT be caught."
fi

echo "0" > "$PHOENIXBOOT_DATA_DIR/panic_count"
echo "$(date +%s)" > "$PHOENIXBOOT_DATA_DIR/last_good_boot"

cat > "$PHOENIXBOOT_DATA_DIR/config" << EOF
ORIG_SHA256="${ORIG_SHA256}"
PATCHED_SHA256="${PATCHED_SHA256}"
BOOT_PARTITION="${BOOT_PARTITION}"
SLOT_SUFFIX="${SLOT_SUFFIX}"
IS_AB="${IS_AB}"
ROOT_MANAGER="${ROOT_MANAGER}"
SECONDARY_LOCATION="${SECONDARY_LOCATION}"
SECONDARY_BACKUP_PATH="${SECONDARY_BACKUP_PATH}"
MISC_PARTITION="${MISC_PARTITION}"
MISC_OFFSET="${MISC_OFFSET}"
USE_MISC_COUNTER="${USE_MISC_COUNTER}"
INSTALL_DATE="$(date +%s)"
INSTALL_DATE_HUMAN="$(date)"
EOF
chmod 600 "$PHOENIXBOOT_DATA_DIR/config"
log_ok "Watchdog configuration written."

if [ "$SYNTHETIC_HEADER" != "true" ]; then
    log_info "Flashing patched boot image..."
    log_warn "DO NOT interrupt power now."

    dd if="$PATCHED_IMG" of="$BOOT_PARTITION" bs=4096 2>/dev/null
    FLASH_EXIT=$?

    [ $FLASH_EXIT -ne 0 ] && {
        log_warn "Flash failed (exit $FLASH_EXIT). Attempting to restore original..."
        dd if="$ORIG_IMG" of="$BOOT_PARTITION" bs=4096 2>/dev/null && \
            log_ok "Original boot image restored." || \
            log_warn "RESTORE ALSO FAILED. Boot partition may be in undefined state. Flash boot_orig.img manually."
        abort_install "Boot flash failed."
    }

    log_ok "Patched boot image flashed successfully."
fi

log_info "Setting file permissions on extracted module files..."
chmod 755 "$MODPATH/service.sh"
chmod 755 "$MODPATH/uninstall.sh"
chmod 755 "$MODPATH/ask_bootloader.sh"
chmod 755 "$MODPATH/system/bin/phoenixboot/boot_abort_handler.sh"
log_ok "Module file permissions set."

log_info "Cleaning up installation workspace..."
rm -rf "$SESSION_TMP"
log_ok "Workspace cleaned."

ui_print " "
ui_print "-----------------------------------------"
ui_print "  PhoenixBoot v1.3 has been installed!   "
ui_print "-----------------------------------------"
if [ "$SYNTHETIC_HEADER" = "true" ]; then
ui_print "  Mode: BOOTCONFIG-ONLY (GKI 2.0)"
else
ui_print "  Mode: PATCHED (panic=5 injected)"
fi
ui_print "  Backups stored in: /data/adb/phoenixboot"
[ "$SECONDARY_LOCATION" != "none" ] && \
ui_print "  Secondary backup found at: /$SECONDARY_LOCATION"
[ "$USE_MISC_COUNTER" = "true" ] && \
ui_print "  Early-boot counter: ACTIVE (/misc)" || \
ui_print "  Early-boot counter: DATA-ONLY"
ui_print " "
ui_print "  Done. Just reboot and you're protected."
ui_print " "
