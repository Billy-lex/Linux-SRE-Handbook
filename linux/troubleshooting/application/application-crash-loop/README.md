# Application Crash Loop

## Problem

A systemd service keeps crashing and restarting repeatedly. The service is configured with `Restart=always` or `Restart=on-failure`, so systemd automatically restarts it after each crash. The service may appear to be "running" when checked briefly, but it is actually cycling between crashes and restarts.

## Symptoms

- `systemctl status` shows the service is active, but `Active: active (running) since ...` shows a very recent start time — suggesting it just restarted.
- Users report intermittent availability — the application works for a moment, then fails, then works again.
- `systemctl status` may show a high restart count or `NRestarts` value.
- System logs show repeated start/stop cycles for the service.
- The service never stabilizes; it crashes seconds or minutes after each restart.

## Troubleshooting

### 1. Check service status and restart count

```bash
systemctl status <service-name>
```

Look for:

- **`Active: active (running) since ...`** — if the "since" timestamp is very recent (seconds or minutes ago), the service may have just restarted.
- **`Main PID`** — note whether the PID changes between checks.
- **Recent log lines** shown at the bottom — they may reveal the crash reason.

### 2. Check the restart count explicitly

```bash
systemctl show <service-name> -p NRestarts
```

This returns the number of times systemd has restarted the service. A high value (e.g., `NRestarts=47`) confirms a crash loop.

### 3. Examine the full service journal

```bash
journalctl -u <service-name> --since "1 hour ago" --no-pager
```

Look for a repeating pattern of:

1. Service started.
2. Error or crash message.
3. Service stopped / exited with non-zero status.
4. Service scheduled for restart.

The crash reason is usually visible in the log lines just before each exit. Common patterns include:

- `Out of memory` or `OOM killed` — memory pressure.
- `Connection refused` or `connection timed out` — a dependency (database, API, cache) is unreachable.
- `Address already in use` — port conflict with another process.
- `Permission denied` or `ENOENT` — missing file or wrong permissions.
- `Segmentation fault` — application bug or corrupted binary.
- `Panic` or unhandled exception — application-level error (e.g., missing configuration, bad input).

### 4. Check if the process was OOM-killed

```bash
dmesg -T | grep -i "oom\|killed process"
```

If the kernel killed the process due to memory pressure, `dmesg` will show entries like:

```
[Sun Sep 20 10:32:15 2026] Out of memory: Killed process 12345 (myapp)
```

Also check the service's memory usage at the time of the crash:

```bash
journalctl -u <service-name> --since "1 hour ago" | grep -i "memory\|oom"
```

### 5. Check the restart policy

```bash
systemctl show <service-name> -p Restart -p RestartSec -p StartLimitBurst -p StartLimitIntervalSec
```

Example output:

```
Restart=always
RestartSec=5s
StartLimitBurst=5
StartLimitIntervalSec=10000000
```

- `Restart=always` means systemd restarts the service unconditionally after it exits.
- `RestartSec` is the delay between restarts.
- `StartLimitBurst` and `StartLimitIntervalSec` control how many restarts are allowed within a time window before systemd gives up. If these are not set (or set very high), the service will restart indefinitely.

### 6. Check whether a dependency is unavailable

Many crash loops are caused by the application failing to connect to a required service:

```bash
# Check if a database is reachable
nc -vz <db-host> 5432

# Check if a cache is reachable
nc -vz <cache-host> 6379
```

If the application depends on another service that is down, it may crash on startup, get restarted by systemd, crash again, and repeat.

### 7. Check for configuration errors

```bash
journalctl -u <service-name> -n 50 --no-pager
```

Look for configuration-related errors in the most recent crash:

- Missing environment variables
- Wrong file paths
- Invalid configuration syntax
- Missing or expired certificates

### 8. Run the application manually to observe the crash

```bash
# Stop the systemd-managed instance first
systemctl stop <service-name>

# Run the binary directly with the same arguments
/path/to/application --config /etc/myapp/config.yaml
```

Running the application interactively shows the full crash output in real time, which may include stack traces or error messages that `journalctl` truncates.

## Root Cause

Common root causes of a crash loop:

- **Missing or unreachable dependency** — the application cannot connect to a database, cache, message queue, or API it requires on startup, so it exits immediately.
- **Configuration error** — wrong path, missing environment variable, invalid config file, or expired certificate causes the application to fail at startup.
- **Out of memory** — the application consumes too much memory and is killed by the OOM killer, then restarted by systemd, repeating the cycle.
- **Port conflict** — another process is already bound to the port the application needs, causing it to exit with "Address already in use."
- **Application bug** — a code defect causes a panic, segfault, or unhandled exception under certain conditions.
- **Insufficient `StartLimitBurst`** — systemd's restart limits are not configured, so the crash loop continues indefinitely instead of stopping after a reasonable number of attempts.

## Resolution

The fix depends on the root cause identified during troubleshooting:

- **Fix the dependency** — start the missing service, fix the network path, or correct the connection string.

- **Fix the configuration** — correct the config file, add the missing environment variable, or update the expired certificate.

- **Increase memory or fix the memory leak** — if OOM is the cause, increase the memory limit or investigate the application's memory usage.

- **Resolve port conflicts** — identify and stop the process occupying the port:

  ```bash
  ss -tlnp | grep <port>
  ```

- **Configure restart limits** to prevent infinite crash loops:

  ```ini
  # In the systemd unit file
  [Service]
  Restart=on-failure
  RestartSec=5s
  StartLimitIntervalSec=300
  StartLimitBurst=3
  ```

  This allows at most 3 restarts within 300 seconds. After that, systemd stops the service and marks it as failed, which is more useful than an infinite crash loop — it makes the problem visible.

- **Fix the application bug** — if the crash is caused by a code defect, apply the fix and restart.

After applying the fix:

```bash
systemctl daemon-reload   # if the unit file was changed
systemctl restart <service-name>
```

## Verification

Confirm the service is stable after the fix:

```bash
systemctl status <service-name>
```

The service should show `Active: active (running)` with a start time that does not keep resetting.

Check that the restart count is no longer increasing:

```bash
systemctl show <service-name> -p NRestarts
```

Monitor the journal for at least a few minutes:

```bash
journalctl -u <service-name> -f
```

No new crash/restart cycles should appear.

## Prevention

- **Set `StartLimitBurst` and `StartLimitIntervalSec`** on all services with `Restart=always` or `Restart=on-failure`. Without these limits, a crash loop can run forever and hide the real problem.
- **Use health checks** or readiness probes to verify the application is actually functional, not just running.
- **Monitor restart frequency** — alert when `NRestarts` exceeds a threshold (e.g., more than 3 restarts in 10 minutes).
- **Handle startup dependencies gracefully** — configure the application to retry connections with backoff instead of exiting immediately when a dependency is unavailable.
- **Keep configuration in version control** so changes can be reviewed and rolled back.
