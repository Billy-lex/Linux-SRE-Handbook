# HTTP 504 Gateway Timeout

## Problem

A reverse proxy (Nginx, Apache, HAProxy) returns HTTP 504 Gateway Timeout. This means the proxy forwarded the request to the backend, but the backend did not respond within the proxy's timeout window. Unlike 502 (backend unreachable) or 503 (backend refusing requests), a 504 means the backend is reachable and accepted the connection — it is simply too slow to finish processing the request.

## Symptoms

- Users see "504 Gateway Timeout" in the browser.
- API calls return HTTP 504 status codes.
- The error is often intermittent — some requests succeed while others time out, depending on what the backend is doing.
- Proxy error logs show messages such as:
  - `upstream timed out (110: Connection timed out)` — Nginx
  - `AH01114: HTTP: failed to make connection to backend` — Apache (with timeout context)
  - `sQ` (session queue) or `sD` (data timeout) flags in HAProxy logs.
- Long-running operations (reports, file uploads, complex queries) are more likely to trigger 504 than simple requests.

## Troubleshooting

> **Host legend:** Each step is marked with where to run it.
> - 🔵 **Proxy** — the reverse proxy host (Nginx / Apache / HAProxy)
> - 🟢 **Backend** — the upstream application server
> - 🔵🟢 **Either** — same-host setup, or run on both as noted

### 1. Confirm the backend is reachable and measure response time

> 🟢 **Backend** (localhost) or 🔵 **Proxy** (pointing at backend IP)

```bash
time curl -v -o /dev/null http://localhost:<backend-port>/
```

If the request eventually returns 200 but takes a long time (e.g., 30+ seconds), the backend is alive but slow. This confirms a 504 scenario rather than a 502 (where the connection would be refused or fail immediately).

### 2. Check the proxy timeout configuration

> 🔵 **Proxy**

For Nginx:

```bash
grep -E 'proxy_read_timeout|proxy_connect_timeout|proxy_send_timeout' /etc/nginx/nginx.conf /etc/nginx/conf.d/*.conf
```

Default values in Nginx:

| Directive | Default |
|-----------|---------|
| `proxy_connect_timeout` | 60s |
| `proxy_read_timeout` | 60s |
| `proxy_send_timeout` | 60s |

If the backend needs more than 60 seconds to respond, the default `proxy_read_timeout` will trigger a 504.

For HAProxy:

```bash
grep -E 'timeout server|timeout connect|timeout client' /etc/haproxy/haproxy.cfg
```

### 3. Identify which requests are timing out

> 🔵 **Proxy**

Check the proxy access log for response times:

```bash
# Nginx (if log_format includes $request_time or $upstream_response_time)
tail -100 /var/log/nginx/access.log | awk '{print $NF, $0}' | sort -rn | head -20
```

Look for requests where the upstream response time exceeds the configured timeout. This helps identify whether the problem affects all requests or only specific endpoints (e.g., `/api/report`, `/api/export`).

### 4. Check backend resource usage

> 🟢 **Backend**

```bash
# CPU and load
top -bn1 | head -15

# Memory
free -h

# Disk I/O (a common cause of slowness)
iostat -x 1 3
```

High CPU, memory pressure, or disk I/O saturation on the backend can cause requests to take much longer than normal.

### 5. Check if the backend is waiting on a slow dependency

> 🟢 **Backend**

The most common cause of intermittent 504 is a slow database query or an external API call:

```bash
# Check for slow database queries (PostgreSQL example)
psql -U <user> -d <database> -c "SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '10 seconds'
ORDER BY duration DESC;"
```

```bash
# Check for slow MySQL queries
mysql -e "SHOW PROCESSLIST;" | grep -v Sleep
```

Long-running queries block application threads and prevent them from responding to the proxy within the timeout window.

### 6. Check backend application logs

> 🟢 **Backend**

```bash
journalctl -u <backend-service> --since "30 minutes ago" --no-pager
```

Look for:

- **Slow query warnings** — the application itself may log queries that exceed a threshold.
- **Deadlocks** — database deadlocks cause transactions to wait until they time out.
- **External API timeouts** — the backend may be calling a third-party service that is slow.
- **Thread/worker exhaustion** — all workers are busy handling slow requests, so new requests queue up.

### 7. Check backend connection and worker pools

> 🟢 **Backend**

```bash
# Number of application workers/processes
ps aux | grep <application-name> | wc -l

# Active connections to the backend
ss -tnp | grep <backend-port> | wc -l

# Database connection pool (PostgreSQL)
psql -U <user> -d <database> -c "SELECT count(*) FROM pg_stat_activity;"
```

If all workers are occupied by slow requests, new requests will queue up and eventually time out at the proxy.

### 8. Check proxy error logs for patterns

> 🔵 **Proxy**

```bash
# Nginx
grep "upstream timed out" /var/log/nginx/error.log | tail -20

# HAProxy
journalctl -u haproxy --since "1 hour ago" | grep -i "timeout\|sQ\|sD"
```

Check whether the timeouts are concentrated on a specific backend server or endpoint. This helps narrow the investigation.

### 9. Compare direct backend response time with proxy response time

> 🔵🟢 **Either**

From the proxy host:

```bash
time curl -o /dev/null http://<backend-ip>:<backend-port>/api/slow-endpoint
```

From the backend host:

```bash
time curl -o /dev/null http://localhost:<backend-port>/api/slow-endpoint
```

If the backend responds within the timeout when called directly but times out through the proxy, the network path between the proxy and backend may be adding latency (packet loss, routing issues, or a congested link).

## Root Cause

Common root causes of HTTP 504:

- **Slow database queries** — a long-running query blocks the application thread, and the proxy gives up waiting.
- **Backend overloaded** — CPU, memory, or I/O pressure causes the backend to process requests much more slowly than normal.
- **Proxy timeout too short** — the backend is legitimately slow for certain operations (e.g., report generation), and the default timeout is insufficient.
- **External dependency slow** — the backend calls a third-party API or service that is slow or degraded, blocking the request.
- **Worker/thread exhaustion** — all backend workers are busy handling slow requests, causing new requests to queue until they time out.
- **Network latency between proxy and backend** — packet loss or congestion on the network path adds unexpected latency.

## Resolution

The fix depends on the root cause identified during troubleshooting:

- **Optimize slow queries** — add indexes, rewrite inefficient queries, or cache results:

  ```sql
  -- PostgreSQL: check for missing indexes on a slow query
  EXPLAIN ANALYZE SELECT ... ;
  ```

- **Increase proxy timeouts** for endpoints that are legitimately slow:

  ```nginx
  # Nginx: increase for specific locations
  location /api/report {
      proxy_read_timeout 300s;
      proxy_connect_timeout 10s;
  }
  ```

  Avoid increasing timeouts globally — only apply longer timeouts to the endpoints that need them.

- **Scale the backend** — add more workers or backend instances to handle concurrent requests without queuing.

- **Add caching** — cache expensive operations so the backend does not recompute them on every request.

- **Implement async processing** — for long-running operations, accept the request immediately and process it in the background (return a job ID, let the client poll for results).

- **Fix external dependency issues** — add timeouts and circuit breakers for third-party API calls so the backend fails fast instead of blocking.

## Verification

After applying the fix, measure response time through the proxy:

> 🔵 **Proxy**

```bash
time curl -o /dev/null -w "HTTP %{http_code}, time: %{time_total}s\n" http://<proxy-host>/api/previously-slow-endpoint
```

The response should return 200 within the configured timeout.

Monitor the proxy error log for continued timeouts:

> 🔵 **Proxy**

```bash
tail -f /var/log/nginx/error.log | grep "upstream timed out"
```

No new timeout entries should appear under normal load.

If possible, run a short load test to confirm stability:

> 🔵 **Proxy**

```bash
# Simple concurrency test (do not run against production)
for i in $(seq 1 20); do
    curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://<proxy-host>/ &
done
wait
```

All responses should be 200 with response times well within the timeout window.

## Prevention

- **Monitor backend response times** — track p50, p95, and p99 latency and alert when they approach the proxy timeout threshold.
- **Set appropriate proxy timeouts per endpoint** — avoid a single global timeout. Endpoints that perform heavy operations should have longer timeouts than simple health checks.
- **Implement query performance monitoring** — log and alert on slow queries before they cause 504 errors.
- **Use async patterns for long-running operations** — never block an HTTP request on a task that might take longer than the proxy timeout.
- **Add circuit breakers** for external dependencies so the backend fails fast instead of waiting for a slow third-party service.
- **Load test before deploying changes** — measure how new code affects response times under realistic traffic.
- **Keep the proxy and backend on a low-latency network** — avoid routing application traffic over congested or high-latency links.
