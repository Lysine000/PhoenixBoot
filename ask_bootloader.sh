#!/system/bin/sh
# PhoenixBoot — bootloader state prompt
# called from customize.sh before any install decisions are made

STATE_FILE=/data/local/tmp/phoenix_boot_state
TIMEOUT=15
CONFIRM_TIMEOUT=3

VOLUP_CODE=115
VOLDN_CODE=114

write_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$1" > "$STATE_FILE"
}

print_prompt() {
    echo ""
    echo "======================================================="
    echo " PhoenixBoot: Declare Your Bootloader Status"
    echo "======================================================="
    echo " Press VOLUME UP   = UNLOCKED  (confirm twice)"
    echo " Press VOLUME DOWN = LOCKED    (once)"
    echo " Waiting 15 seconds..."
    echo "======================================================="
    echo ""
}

print_prompt > /dev/kmsg  2>/dev/null || true
print_prompt > /dev/tty0  2>/dev/null || true
print_prompt              2>/dev/null || true

if ! command -v getevent >/dev/null 2>&1; then
    sleep "$TIMEOUT"
    write_state "locked"
    exit 0
fi

# Build list of usable input nodes.
NODES=""
for _node in /dev/input/event*; do
    [ -c "$_node" ] || continue
    getevent -p "$_node" >/dev/null 2>&1 && NODES="$NODES $_node"
done

if [ -z "$NODES" ]; then
    sleep "$TIMEOUT"
    write_state "locked"
    exit 0
fi

VOLUP_HEX=$(printf "%04x" $VOLUP_CODE)
VOLDN_HEX=$(printf "%04x" $VOLDN_CODE)

RESULT_FILE=/data/local/tmp/phoenix_key_result
PID_FILE=/data/local/tmp/phoenix_pids
rm -f "$RESULT_FILE" "$PID_FILE"

start_readers() {
    rm -f "$RESULT_FILE" "$PID_FILE"
    for _node in $NODES; do
        (
            getevent -l "$_node" 2>/dev/null | while IFS= read -r _line; do
                # Labeled format: [timestamp] EV_KEY KEY_VOLUMEUP DOWN
                case "$_line" in
                    *EV_KEY*KEY_VOLUMEUP*DOWN*)
                        echo "volup" > "$RESULT_FILE"; exit 0 ;;
                    *EV_KEY*KEY_VOLUMEDOWN*DOWN*)
                        echo "voldn" > "$RESULT_FILE"; exit 0 ;;
                esac
                # Raw hex fallback for older getevent without -l label support
                _type=$(echo "$_line" | awk '{print $2}')
                _code=$(echo "$_line" | awk '{print $3}')
                _val=$(echo  "$_line" | awk '{print $4}')
                if [ "$_type" = "0001" ] && [ "$_val" = "00000001" ]; then
                    case "$_code" in
                        "$VOLUP_HEX") echo "volup" > "$RESULT_FILE"; exit 0 ;;
                        "$VOLDN_HEX") echo "voldn" > "$RESULT_FILE"; exit 0 ;;
                    esac
                fi
            done
        ) &
        echo "$!" >> "$PID_FILE"
    done
}

kill_readers() {
    if [ -f "$PID_FILE" ]; then
        while IFS= read -r _pid; do
            kill "$_pid" 2>/dev/null || true
        done < "$PID_FILE"
        rm -f "$PID_FILE"
    fi
}

wait_for_result() {
    local _deadline=$(( $(date +%s) + $1 ))
    while [ "$(date +%s)" -lt "$_deadline" ]; do
        if [ -f "$RESULT_FILE" ]; then
            cat "$RESULT_FILE"
            rm -f "$RESULT_FILE"
            return 0
        fi
        usleep 200000 2>/dev/null || sleep 1
    done
    echo "timeout"
    return 1
}

start_readers
key=$(wait_for_result $TIMEOUT)
kill_readers

case "$key" in
    volup)
        echo " VOLUME UP detected — press VOLUME UP again within ${CONFIRM_TIMEOUT}s to confirm UNLOCKED" > /dev/kmsg 2>/dev/null || true

        start_readers
        confirm=$(wait_for_result $CONFIRM_TIMEOUT)
        kill_readers

        if [ "$confirm" = "volup" ]; then
            write_state "unlocked"
            echo " -> State: UNLOCKED" > /dev/kmsg 2>/dev/null || true
        else
            write_state "locked"
            echo " -> Confirm missed — defaulting to LOCKED" > /dev/kmsg 2>/dev/null || true
        fi
        ;;
    voldn)
        write_state "locked"
        echo " -> State: LOCKED" > /dev/kmsg 2>/dev/null || true
        ;;
    *)
        write_state "locked"
        echo " -> Timed out — defaulting to LOCKED" > /dev/kmsg 2>/dev/null || true
        ;;
esac

rm -f "$RESULT_FILE" "$PID_FILE"
exit 0
