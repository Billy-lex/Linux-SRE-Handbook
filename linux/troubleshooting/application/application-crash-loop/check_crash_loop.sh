#!/usr/bin/env bash
# check_crash_loop.sh - Detect systemd services that are restarting too frequently.
#
# Usage:
#   ./check_crash_loop.sh [MAX_RESTARTS]
#
# Arguments:
#   MAX_RESTARTS  Maximum acceptable NRestarts value (default: 3)
#
# Exit status:
#   0  No service exceeds the restart threshold
#   1  One or more services are crash-looping

set -euo pipefail

MAX_RESTARTS="${1:-3}"

if ! [[ "$MAX_RESTARTS" =~ ^[0-9]+$ ]]; then
    echo "Error: MAX_RESTARTS must be a positive integer." >&2
    exit 1
fi

alert_found=0

while IFS= read -r service; do
    [ -z "$service" ] && continue

    # Use systemd's built-in restart counter (more accurate than parsing logs)
    restart_count=$(systemctl show "$service" -p NRestarts --value 2>/dev/null || echo "0")

    if ! [[ "$restart_count" =~ ^[0-9]+$ ]]; then
        continue
    fi

    if [ "$restart_count" -gt "$MAX_RESTARTS" ]; then
        status=$(systemctl show "$service" -p ActiveState --value 2>/dev/null)
        echo "WARNING: $service has NRestarts=$restart_count (threshold: $MAX_RESTARTS) — state: $status"
        alert_found=1
    fi
done < <(systemctl list-units --type=service --state=active --no-pager --no-legend 2>/dev/null | awk '{print $1}')

if [ "$alert_found" -eq 1 ]; then
    echo ""
    echo "Action required: investigate the affected service(s) for crash loops."
    exit 1
else
    echo "OK: No active service exceeded $MAX_RESTARTS restarts."
    exit 0
fi
