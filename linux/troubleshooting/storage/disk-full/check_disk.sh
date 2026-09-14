#!/usr/bin/env bash
# check_disk.sh - Check disk usage and alert when a filesystem exceeds the threshold.
#
# Usage:
#   ./check_disk.sh [THRESHOLD]
#
# Arguments:
#   THRESHOLD  Percentage at which to warn (default: 80)
#
# Exit status:
#   0  All filesystems are below the threshold
#   1  One or more filesystems are at or above the threshold

set -euo pipefail

THRESHOLD="${1:-80}"

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 100 ]; then
    echo "Error: THRESHOLD must be an integer between 1 and 100." >&2
    exit 1
fi

alert_found=0

while IFS= read -r line; do
    usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')
    filesystem=$(echo "$line" | awk '{print $1}')

    # Skip lines where usage is not a valid number
    if ! [[ "$usage" =~ ^[0-9]+$ ]]; then
        continue
    fi

    if [ "$usage" -ge "$THRESHOLD" ]; then
        echo "WARNING: ${mount} (${filesystem}) is at ${usage}% usage (threshold: ${THRESHOLD}%)"
        alert_found=1
    fi
done < <(df -hP -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2)

if [ "$alert_found" -eq 1 ]; then
    echo ""
    echo "Action required: free up space or expand the affected filesystem(s)."
    exit 1
else
    echo "OK: All filesystems are below ${THRESHOLD}% usage."
    exit 0
fi
