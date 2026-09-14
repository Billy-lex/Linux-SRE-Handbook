#!/usr/bin/env bash
# check_io.sh - Check disk I/O utilization and alert when a device exceeds thresholds.
#
# Usage:
#   ./check_io.sh [UTIL_THRESHOLD] [AWAIT_THRESHOLD]
#
# Arguments:
#   UTIL_THRESHOLD   Disk utilization percentage threshold (default: 90)
#   AWAIT_THRESHOLD  Average I/O wait time in ms threshold (default: 50)
#
# Exit status:
#   0  All devices are below thresholds
#   1  One or more devices exceed thresholds

set -euo pipefail

UTIL_THRESHOLD="${1:-90}"
AWAIT_THRESHOLD="${2:-50}"

if ! [[ "$UTIL_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$UTIL_THRESHOLD" -lt 1 ] || [ "$UTIL_THRESHOLD" -gt 100 ]; then
    echo "Error: UTIL_THRESHOLD must be an integer between 1 and 100." >&2
    exit 1
fi

if ! [[ "$AWAIT_THRESHOLD" =~ ^[0-9]+$ ]]; then
    echo "Error: AWAIT_THRESHOLD must be a positive integer." >&2
    exit 1
fi

if ! command -v iostat &>/dev/null; then
    echo "Error: iostat not found. Install sysstat:" >&2
    echo "  RHEL/CentOS: dnf install sysstat" >&2
    echo "  Debian/Ubuntu: apt-get install sysstat" >&2
    exit 1
fi

alert_found=0
alerts=""
diagnostics=""

# Parse iostat -x output (2 samples, skip the first interval which is since boot).
# Column layout varies by sysstat version:
#   Old: Device  r/s  w/s  ...  await  ...  %util
#   New: Device  r/s  rkB/s  ...  r_await  w_await  ...  %util
# Detect the available columns dynamically from the header.
util_col=""
await_col=""
r_await_col=""
w_await_col=""
sample=0

while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    if [[ "$line" == Device* ]]; then
        sample=$((sample + 1))
        col=0
        util_col=""
        await_col=""
        r_await_col=""
        w_await_col=""
        for field in $line; do
            case "$field" in
                %util)    util_col=$col ;;
                await)    await_col=$col ;;
                r_await)  r_await_col=$col ;;
                w_await)  w_await_col=$col ;;
            esac
            col=$((col + 1))
        done
        continue
    fi

    # Only process data lines from the second sample (first is since boot)
    if [[ "$sample" -ge 2 ]] && [[ "$line" != avg-cpu:* ]] && [[ "$line" != Linux* ]]; then
        device=$(echo "$line" | awk '{print $1}')
        # Skip non-device lines (e.g. numeric-only summary rows)
        [[ ! "$device" =~ ^[a-z] ]] && continue

        if [ -n "$util_col" ]; then
            util=$(echo "$line" | awk -v c=$((util_col + 1)) '{printf "%.0f", $c}')
            if [ "$util" -ge "$UTIL_THRESHOLD" ]; then
                alerts="${alerts}WARNING: ${device} — util ${util}% (threshold: ${UTIL_THRESHOLD}%)\n"
                alert_found=1
            fi
        fi

        # Check await: use single "await" column if present, otherwise max(r_await, w_await)
        await=""
        if [ -n "$await_col" ]; then
            await=$(echo "$line" | awk -v c=$((await_col + 1)) '{printf "%.0f", $c}')
        elif [ -n "$r_await_col" ] && [ -n "$w_await_col" ]; then
            await=$(echo "$line" | awk -v rc=$((r_await_col + 1)) -v wc=$((w_await_col + 1)) \
                '{v = ($rc > $wc) ? $rc : $wc; printf "%.0f", v}')
        fi

        if [ -n "$await" ] && [ "$await" -ge "$AWAIT_THRESHOLD" ]; then
            alerts="${alerts}WARNING: ${device} — await ${await}ms (threshold: ${AWAIT_THRESHOLD}ms)\n"
            alert_found=1
        fi
    fi
done < <(iostat -x 1 2 2>/dev/null)

# Collect diagnostic data when alert is triggered
if [ "$alert_found" -eq 1 ]; then
    if command -v iotop &>/dev/null; then
        diagnostics+="--- Top I/O processes (iotop) ---\n"
        diagnostics+="$(iotop -b -o -n 1 2>/dev/null | head -15)\n"
    fi

    if command -v vmstat &>/dev/null; then
        diagnostics+="\n--- vmstat (3 samples) ---\n"
        diagnostics+="$(vmstat 1 3)\n"
    fi

    echo -e "$alerts"
    echo -e "$diagnostics"
    echo "Action required: investigate I/O saturation on the affected device(s)."
    exit 1
else
    echo "OK: All devices below thresholds (util: ${UTIL_THRESHOLD}%, await: ${AWAIT_THRESHOLD}ms)."
    exit 0
fi
