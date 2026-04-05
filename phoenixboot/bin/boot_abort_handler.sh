#!/system/bin/sh
MISC_OFFSET=53248
MAX_PANIC_COUNT=127

MISC_PART=""
# ueventd populates /dev/block symlinks asynchronously at early-init.
# Poll for up to 1 second (10 x 100 ms) before giving up so we don't
# silently skip the counter increment on a fast-executing early-init.
_retries=10
while [ $_retries -gt 0 ]; do
    for cand in /dev/block/bootdevice/by-name/misc /dev/block/by-name/misc; do
        [ -b "$cand" ] && { MISC_PART="$cand"; break 2; }
    done
    _retries=$(( _retries - 1 ))
    [ $_retries -gt 0 ] && sleep 0.1
done

[ -z "$MISC_PART" ] && exit 0

RAW=$(dd if="$MISC_PART" bs=1 skip="$MISC_OFFSET" count=9 2>/dev/null | od -A n -t x1 | tr -d ' \n')
MAGIC_SEGMENT="${RAW:0:16}"

if [ "$MAGIC_SEGMENT" = "50484e5842540100" ]; then
    COUNTER_HEX="${RAW:16:2}"
    COUNTER=$(printf '%d' "0x${COUNTER_HEX}" 2>/dev/null || echo 0)
    COUNTER=$(( COUNTER + 1 ))
    [ "$COUNTER" -gt "$MAX_PANIC_COUNT" ] && COUNTER=$MAX_PANIC_COUNT
    printf "\\$(printf '%03o' $COUNTER)" | \
        dd of="$MISC_PART" bs=1 seek=$(( MISC_OFFSET + 8 )) count=1 conv=notrunc 2>/dev/null
fi

exit 0
