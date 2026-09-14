# Port Not Listening

## Problem

A service that should be accepting connections on a specific port is not reachable. Clients receive "connection refused" errors, and health checks fail.

## Symptoms

- Clients get "Connection refused" when trying to connect to the service
- Health checks or monitoring alerts report the service as down
- `curl`, `telnet`, or application clients cannot reach the expected port
- The service may appear to be running but is not accepting connections

## Troubleshooting

### Step 1: Check which ports are currently listening

```bash
ss -tlnp
```

This shows all listening TCP ports along with the process that owns each one. Look for the expected port in the `Local Address:Port` column and confirm the associated process in the `Process` column.

### Step 2: Check the specific port

```bash
ss -tlnp | grep <port>
```

If no output is returned, nothing is listening on that port. This narrows the problem to either the service not running or not binding to the expected port.

### Step 3: Check whether the service is running

```bash
systemctl status <service>
```

Look at whether the service is `active (running)` or `inactive (dead)` / `failed`. Check the most recent log lines for errors that prevented the service from starting:

```bash
journalctl -u <service> --no-pager -n 50
```

### Step 4: Check the bind address

A service might be listening, but only on `127.0.0.1` (localhost). This means it accepts connections from the local machine only, not from other hosts.

```bash
ss -tlnp | grep <port>
```

Compare:

- `127.0.0.1:<port>` — localhost only, not reachable from other machines
- `0.0.0.0:<port>` or `:::<port>` — all interfaces, reachable externally

If the service is bound to `127.0.0.1` but remote clients need access, update the service configuration to bind to `0.0.0.0` or the specific interface address, then restart the service.

### Step 5: Check firewall rules

The service may be listening correctly, but the firewall is dropping incoming connections.

For `iptables`:

```bash
iptables -L -n
```

For `firewalld`:

```bash
firewall-cmd --list-all
```

Look for rules that accept traffic on the expected port. If the port is not listed, add it:

```bash
# firewalld
firewall-cmd --permanent --add-port=<port>/tcp
firewall-cmd --reload

# iptables
iptables -A INPUT -p tcp --dport <port> -j ACCEPT
```

### Step 6: Check SELinux

On SELinux-enforcing systems, the security policy can prevent a service from binding to a non-standard port.

```bash
getenforce
```

If the result is `Enforcing`, check the audit log for denials:

```bash
grep denied /var/log/audit/audit.log | grep <port>
```

If SELinux is blocking the port, allow it:

```bash
semanage port -a -t http_port_t -p tcp <port>
```

Use the correct SELinux port type for the service (e.g., `http_port_t` for web servers).

### Step 7: Test local connectivity

Even if the port appears in `ss` output, verify that the service actually responds:

```bash
curl -v http://localhost:<port>
```

Or:

```bash
telnet localhost <port>
```

If local connections also fail, the problem is with the service itself (crashed, misconfigured, or not fully started). If local connections succeed but remote connections fail, the problem is the bind address, firewall, or SELinux.

## Root Cause

Common root causes include:

- **Service not started** — the service was never started or is not enabled at boot
- **Service crashed** — the service failed to start or exited due to a configuration error, missing dependency, or resource issue
- **Wrong bind address** — the service is bound to `127.0.0.1` instead of `0.0.0.0`, so it only accepts local connections
- **Firewall blocking** — `iptables` or `firewalld` rules do not allow incoming traffic on the port
- **SELinux policy blocking** — SELinux prevents the service from binding to a non-standard port

## Resolution

The fix depends on the root cause identified:

**Service not started:**

```bash
systemctl start <service>
systemctl enable <service>
```

**Service crashed:** Investigate the logs with `journalctl -u <service>`, fix the underlying error (configuration, missing files, resource limits), then restart:

```bash
systemctl restart <service>
```

**Wrong bind address:** Update the service configuration file to bind to `0.0.0.0` or the correct interface, then restart the service.

**Firewall blocking:** Add the port to the firewall rules (see Step 5 above).

**SELinux blocking:** Add the port to the appropriate SELinux port type (see Step 6 above).

## Verification

After applying the fix, confirm the port is listening:

```bash
ss -tlnp | grep <port>
```

Confirm the service responds locally:

```bash
curl -v http://localhost:<port>
```

If remote access is expected, test from another host:

```bash
curl -v http://<server-ip>:<port>
```

Confirm the firewall allows the port:

```bash
firewall-cmd --list-ports
```

Monitor the service for a period to ensure it remains stable:

```bash
systemctl status <service>
```

## Prevention

- Set up port monitoring (e.g., Prometheus blackbox exporter, Zabbix TCP checks) to detect when a port stops responding
- Configure service health checks so failures are caught before users report them
- Enable services at boot with `systemctl enable` to survive reboots
- Document firewall rules and review them when deploying new services
- Use `systemd` `Restart=always` or `Restart=on-failure` in service units to automatically recover from crashes
- Test connectivity after every service deployment or firewall change
