#!/usr/bin/env bash
# check_503.sh - Probe a URL and report when HTTP 503 is returned.
#
# Usage:
#   ./check_503.sh <URL> [RETRIES] [INTERVAL]
#
# Arguments:
#   URL       The URL to probe (required)
#   RETRIES   Number of retry attempts before reporting failure (default: 3)
#   INTERVAL  Seconds between retries (default: 5)
#
# Exit status:
#   0  URL returned a non-503 response
#   1  URL returned 503 after all retries

set -euo pipefail

URL="${1:-}"
RETRIES="${2:-3}"
INTERVAL="${3:-5}"

if [ -z "$URL" ]; then
    echo "Usage: $0 <URL> [RETRIES] [INTERVAL]" >&2
    exit 1
fi

if ! [[ "$RETRIES" =~ ^[0-9]+$ ]] || [ "$RETRIES" -lt 1 ]; then
    echo "Error: RETRIES must be a positive integer." >&2
    exit 1
fi

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
    echo "Error: INTERVAL must be a positive integer." >&2
    exit 1
fi

attempt=0
while [ "$attempt" -lt "$RETRIES" ]; do
    attempt=$((attempt + 1))

    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$URL" 2>/dev/null || echo "000")

    if [ "$http_code" != "503" ] && [ "$http_code" != "000" ]; then
        echo "OK: $URL returned HTTP $http_code (attempt $attempt/$RETRIES)"
        exit 0
    fi

    if [ "$http_code" = "000" ]; then
        echo "WARN: $URL unreachable (attempt $attempt/$RETRIES)"
    else
        echo "WARN: $URL returned HTTP 503 (attempt $attempt/$RETRIES)"
    fi

    if [ "$attempt" -lt "$RETRIES" ]; then
        sleep "$INTERVAL"
    fi
done

echo ""
echo "FAIL: $URL returned 503 or was unreachable after $RETRIES attempts."
exit 1
