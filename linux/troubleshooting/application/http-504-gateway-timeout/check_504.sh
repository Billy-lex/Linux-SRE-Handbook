#!/usr/bin/env bash
# check_504.sh - Probe a URL and report slow responses or HTTP 504.
#
# Usage:
#   ./check_504.sh <URL> [TIMEOUT_SEC] [RETRIES]
#
# Arguments:
#   URL          The URL to probe (required)
#   TIMEOUT_SEC  Maximum acceptable response time in seconds (default: 30)
#   RETRIES      Number of retry attempts (default: 3)
#
# Exit status:
#   0  URL responded within the timeout
#   1  URL returned 504 or exceeded the timeout

set -euo pipefail

URL="${1:-}"
TIMEOUT_SEC="${2:-30}"
RETRIES="${3:-3}"

if [ -z "$URL" ]; then
    echo "Usage: $0 <URL> [TIMEOUT_SEC] [RETRIES]" >&2
    exit 1
fi

if ! [[ "$TIMEOUT_SEC" =~ ^[0-9]+$ ]] || [ "$TIMEOUT_SEC" -lt 1 ]; then
    echo "Error: TIMEOUT_SEC must be a positive integer." >&2
    exit 1
fi

if ! [[ "$RETRIES" =~ ^[0-9]+$ ]] || [ "$RETRIES" -lt 1 ]; then
    echo "Error: RETRIES must be a positive integer." >&2
    exit 1
fi

attempt=0
while [ "$attempt" -lt "$RETRIES" ]; do
    attempt=$((attempt + 1))

    result=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" --max-time "$TIMEOUT_SEC" "$URL" 2>/dev/null || echo "000 0")
    http_code=$(echo "$result" | awk '{print $1}')
    response_time=$(echo "$result" | awk '{print $2}')

    if [ "$http_code" = "504" ]; then
        echo "WARN: $URL returned HTTP 504 in ${response_time}s (attempt $attempt/$RETRIES)"
    elif [ "$http_code" = "000" ]; then
        echo "WARN: $URL timed out after ${TIMEOUT_SEC}s (attempt $attempt/$RETRIES)"
    else
        echo "OK: $URL returned HTTP $http_code in ${response_time}s (attempt $attempt/$RETRIES)"
        exit 0
    fi

    if [ "$attempt" -lt "$RETRIES" ]; then
        sleep 3
    fi
done

echo ""
echo "FAIL: $URL returned 504 or timed out after $RETRIES attempts."
exit 1
