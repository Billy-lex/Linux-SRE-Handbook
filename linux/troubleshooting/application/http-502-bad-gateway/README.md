# HTTP 502 Bad Gateway

## Problem

A reverse proxy (Nginx, Apache, HAProxy) returns HTTP 502 Bad Gateway. This means the proxy accepted the client request but could not get a valid response from the upstream backend application server. The proxy is working — the backend is not.

## Symptoms

- Users see "502 Bad Gateway" in the browser.
- API calls return HTTP 502 status codes.
- Reverse proxy error logs show upstream connection errors such as:
  - `connect() failed (111: Connection refused)` — backend is not running or not listening.
  - `upstream timed out (110: Connection timed out)` — backend is too slow or overloaded.
  - `no live upstreams` — all backend servers failed health checks.

## Troubleshooting

### 1. Check if the backend application is running

```bash
systemctl status <backend-service>
```

If the service is stopped or failed, this is the most likely cause. Check the active state and any recent failure messages.

### 2. Check if the backend is listening on the expected port

```bash
ss -tlnp | grep <port>
```

Confirm the backend process is bound to the correct address and port. A common mistake is the backend listening on `127.0.0.1` while the proxy connects to a different address, or listening on a different port than what the proxy configuration expects.

### 3. Connect to the backend directly (bypass the proxy)

```bash
curl -v http://localhost:<backend-port>/
```

If this succeeds, the backend is healthy and the problem is in the proxy configuration or the network path between them. If this also fails, the backend itself is the problem.

### 4. Check reverse proxy error logs

For Nginx:

```bash
tail -50 /var/log/nginx/error.log
```

For Apache:

```bash
tail -50 /var/log/httpd/error_log
```

For HAProxy:

```bash
journalctl -u haproxy --since "1 hour ago"
```

The error log tells you whether the proxy got a connection refused, a timeout, or an invalid response from the backend. This narrows the investigation significantly.

### 5. Check the proxy configuration

Verify that the upstream address and port in the proxy configuration match where the backend is actually listening.

For Nginx, check the `proxy_pass` or `upstream` block:

```bash
grep -r proxy_pass /etc/nginx/
```

For Apache, check `ProxyPass` directives:

```bash
grep -r ProxyPass /etc/httpd/conf/
```

A mismatch between the configured upstream and the actual backend address is a common cause of 502 errors.

### 6. Check if the backend is overloaded or too slow

If the backend is running but responds very slowly, the proxy may time out before getting a response. Check the proxy timeout settings:

For Nginx:

```bash
grep -E 'proxy_read_timeout|proxy_connect_timeout|proxy_send_timeout' /etc/nginx/nginx.conf /etc/nginx/conf.d/*.conf
```

Default `proxy_read_timeout` in Nginx is 60 seconds. If the backend needs more time to process requests, increase this value.

### 7. Check firewall rules between proxy and backend

If the proxy and backend are on different hosts, firewall rules may be blocking the connection:

```bash
iptables -L -n
```

```bash
firewall-cmd --list-all
```

On the same host, SELinux or local firewall rules can also prevent the proxy from connecting to the backend port.

### 8. Check backend application logs for crashes or errors

```bash
journalctl -u <backend-service> --since "1 hour ago"
```

Look for out-of-memory kills, unhandled exceptions, database connection failures, or any error that causes the backend to stop responding.

## Root Cause

Common root causes of HTTP 502:

- **Backend application crashed or stopped** — the service is no longer running.
- **Backend not listening on expected port or address** — configuration mismatch between the proxy and the backend.
- **Proxy misconfigured** — wrong upstream address, port, or protocol (e.g., HTTP vs HTTPS).
- **Proxy timeout too short** — the backend is slow to respond and the proxy gives up before the backend finishes.
- **Firewall blocking traffic** — network rules prevent the proxy from reaching the backend.
- **Backend overloaded** — the backend cannot handle the request volume and either queues requests until they time out or refuses new connections.

## Resolution

- **Restart the backend service** if it has crashed or stopped:

  ```bash
  systemctl restart <backend-service>
  ```

- **Fix the proxy configuration** if the upstream address or port is wrong, then reload:

  ```bash
  nginx -t && systemctl reload nginx
  ```

- **Increase proxy timeouts** if the backend is legitimately slow:

  ```nginx
  proxy_connect_timeout 10s;
  proxy_read_timeout 120s;
  proxy_send_timeout 60s;
  ```

- **Fix firewall rules** to allow traffic from the proxy to the backend port.

- **Scale the backend** if it is overloaded — add more backend instances or increase resources.

## Verification

After applying the fix, confirm the backend responds directly:

```bash
curl -v http://localhost:<backend-port>/
```

Then test through the proxy:

```bash
curl -v http://<proxy-host>/
```

Check the proxy error log for new errors:

```bash
tail -10 /var/log/nginx/error.log
```

Confirm the backend service is stable:

```bash
systemctl status <backend-service>
```

Monitor for a few minutes to ensure 502 errors do not recur.

## Prevention

- **Configure health checks** in the reverse proxy so it stops sending traffic to unhealthy backends and returns a meaningful error instead of 502.
- **Tune proxy timeouts** based on the expected response time of the backend. Avoid using very short timeouts for backends that perform long-running operations.
- **Monitor backend availability** with a monitoring system (Prometheus, Zabbix, Nagios) and alert when the backend stops responding.
- **Use circuit breakers** or retries with backoff in the proxy or application layer to handle transient backend failures gracefully.
- **Keep backend and proxy configurations in sync** — when changing the backend port or address, update the proxy configuration at the same time.
