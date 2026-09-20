# Application Crash Loop

## Problem

A systemd service keeps crashing and restarting. With `Restart=always` or `Restart=on-failure`, systemd automatically restarts it after each crash. The service may appear to be "running" when checked briefly, but it is actually cycling between crashes and restarts.

## Symptoms

- `systemctl status` shows a very recent start time — the service just restarted.
- Users report intermittent availability.
- `NRestarts` value is high.
- Logs show repeated start → crash → restart cycles.

## Troubleshooting

### 1. Confirm Crash Loop

```bash
systemctl status <service-name>
systemctl show <service-name> -p NRestarts
```

- If `Active: active (running) since ...` shows a timestamp only seconds or minutes ago, the service likely just restarted.
- If `NRestarts` is a high number (e.g., 47), this strongly suggests a crash loop.

To watch it happening in real time:

```bash
journalctl -u <service-name> -f
```

Look for a repeating pattern: **Started → error → Stopped → Scheduled restart → Started → ...**

### 2. Find the Exit Reason

```bash
journalctl -u <service-name> --since "1 hour ago" --no-pager
```

Focus on the log lines just before each exit. Common patterns:

| Log pattern | Meaning |
|---|---|
| `Out of memory`, `OOM killed` | Kernel killed the process due to memory pressure |
| `Connection refused`, `connection timed out` | A dependency (database, cache, API) is unreachable |
| `Address already in use` | Another process occupies the required port |
| `Permission denied`, `ENOENT` | Missing file or wrong permissions |
| `Segmentation fault` | Application bug or corrupted binary |
| `Panic`, `unhandled exception` | Application-level error (bad config, missing variable) |

For OOM specifically, check the kernel messages in the journal:

```bash
journalctl -k --since "1 hour ago" | grep -Ei "oom|out of memory|killed process"
```

If the journal output is truncated, run the application manually to see the full crash output. First, check the unit file to replicate the execution environment:

```bash
systemctl cat <service-name>
```

Note the `ExecStart`, `User`, `EnvironmentFile`, and `WorkingDirectory` directives, then run accordingly:

```bash
systemctl stop <service-name>
# Match the User, WorkingDirectory, and environment from the unit file
sudo -u <user> /path/to/application --config /etc/myapp/config.yaml
```

### 3. Categorize the Root Cause

Based on the exit reason found in step 2, classify it into one of four categories:

| Category | Typical exit reason | How to confirm |
|---|---|---|
| **Application** | Segfault, panic, unhandled exception | Stack trace in journal; reproduces when run manually |
| **Dependency** | Connection refused/timed out to database, cache, or API | `nc -vz <dep-host> <port>` fails |
| **Resource** | OOM killed, high memory usage | `journalctl -k` OOM entries; `free -h` shows low available memory |
| **Configuration** | Permission denied, ENOENT, invalid config, missing env var | Error message points to a specific file or variable |

Also check the restart policy — if `StartLimitBurst` is not set, the crash loop will run indefinitely:

```bash
systemctl show <service-name> -p Restart -p RestartSec -p StartLimitBurst -p StartLimitIntervalSec
```

### 4. Fix

Apply the fix that matches the category:

**Application** — fix the code defect, update the binary, or apply the patch. Then restart.

**Dependency** — start the missing service, fix the connection string, or correct the network path:

```bash
nc -vz <db-host> 5432   # verify the dependency is now reachable
systemctl restart <service-name>
```

**Resource** — increase memory limit, fix the memory leak, or reduce the application's memory footprint.

**Configuration** — correct the config file, add the missing environment variable, fix file permissions, or update the expired certificate.

**Prevent infinite loops** — configure restart limits so systemd stops retrying after a reasonable number of attempts:

```ini
[Unit]
StartLimitIntervalSec=300
StartLimitBurst=3

[Service]
Restart=on-failure
RestartSec=5s
```

This limits how frequently systemd will attempt to start the service within the configured time window. Once the limit is reached, systemd marks the service as failed — making the problem visible instead of hiding it behind an endless restart cycle.

```bash
systemctl daemon-reload   # if the unit file was changed
systemctl restart <service-name>
```

### 5. Verify Stability

```bash
systemctl status <service-name>
```

The service should show `Active: active (running)` with a start time that does not keep resetting.

```bash
systemctl show <service-name> -p NRestarts
```

`NRestarts` should stop increasing.

```bash
journalctl -u <service-name> -f
```

Monitor for a few minutes — no new crash/restart cycles should appear.

## Prevention

- **Set `StartLimitBurst` and `StartLimitIntervalSec`** on all services with auto-restart enabled.
- **Monitor restart frequency** — alert when `NRestarts` exceeds a threshold.
- **Handle startup dependencies gracefully** — retry with backoff instead of exiting immediately.
- **Use health checks** to verify the application is actually functional, not just running.
- **Keep configuration in version control** for quick rollback.
