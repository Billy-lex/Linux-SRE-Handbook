# Service Failed to Start

## Problem

A systemd-managed service fails to start or enters a "failed" state, leaving the application unavailable to users.

## Symptoms

- `systemctl status <service>` shows the state as `failed`
- The application process is not running
- Users report the service is unavailable
- The service may start briefly and then crash immediately

## Troubleshooting

### Step 1: Check the current service state

```bash
systemctl status <service>
```

This shows whether the service is active, failed, or inactive. Look at the `Active:` line and the most recent log lines displayed at the bottom. The `Main PID` line tells you whether a process exists or whether it exited.

### Step 2: Get detailed service logs

```bash
journalctl -u <service> --no-pager -n 50
```

This pulls the last 50 log entries for the specific service unit. Look for error messages, warnings, or panic/crash output that explains why the service stopped.

If the service has failed across multiple boots, check the previous boot's logs:

```bash
journalctl -u <service> -b -1
```

### Step 3: Review the unit file configuration

```bash
systemctl cat <service>
```

This displays the full unit file (including any drop-in overrides). Check:
- `ExecStart=` — does the path point to a valid executable?
- `User=` / `Group=` — does the specified user exist?
- `WorkingDirectory=` — does the directory exist?
- `Environment=` or `EnvironmentFile=` — are required variables set?
- `After=` / `Requires=` — are dependencies correct?

### Step 4: Check if the binary or executable exists

```bash
which <binary>
```

Or, if the unit file specifies an absolute path:

```bash
ls -la /path/to/binary
```

Confirm the file exists and has execute permission. A missing or non-executable binary is a common reason for immediate failure.

### Step 5: Check if required ports are already in use

```bash
ss -tlnp | grep <port>
```

If another process is already bound to the port the service needs, the service will fail to start. Identify the conflicting process from the `ss` output and decide whether to stop it or reconfigure the service.

### Step 6: Check for configuration file errors

Many services provide a built-in config validation command. For example:

```bash
nginx -t
```

```bash
httpd -t
```

```bash
named-checkconf
```

Run the appropriate validation command for the service. A syntax error in the configuration file will prevent startup even if the unit file and binary are correct.

### Step 7: Check file permissions on required directories

```bash
ls -la /var/lib/<service>/
ls -la /etc/<service>/
ls -la /var/log/<service>/
```

If the service runs as a non-root user, it must have read/write access to its data, configuration, and log directories. Permission denied errors are a frequent cause of startup failures.

## Root Cause

Common root causes include:

- **Misconfigured unit file** — wrong `ExecStart` path, incorrect `User`, missing `Environment` variables
- **Missing dependencies** — a required package, library, or service is not installed or not started
- **Port already in use** — another process holds the port the service needs
- **Bad configuration file** — syntax error or invalid directive in the service's own config
- **Missing environment variables** — the service depends on variables that are not set in the unit file or environment file
- **Permission issues** — the service user cannot access required files, directories, or sockets

## Resolution

The fix depends on the root cause identified:

**Misconfigured unit file:** Edit the unit file (or create a drop-in override), then reload systemd and restart:

```bash
systemctl daemon-reload
systemctl restart <service>
```

**Missing dependency:** Install the required package or start the dependency service first.

**Port conflict:** Stop or reconfigure the process occupying the port:

```bash
systemctl stop <conflicting-service>
systemctl start <service>
```

**Bad configuration file:** Fix the syntax error identified by the config validation command, then restart the service.

**Missing environment variables:** Add them to the unit file or the `EnvironmentFile`:

```ini
[Service]
Environment="KEY=value"
```

Then reload and restart:

```bash
systemctl daemon-reload
systemctl restart <service>
```

**Permission issues:** Fix ownership or permissions on the affected directory:

```bash
chown -R <service-user>:<service-group> /var/lib/<service>
chmod 750 /var/lib/<service>
```

## Verification

After applying the fix, confirm the service starts and stays running:

```bash
systemctl status <service>
```

The `Active:` line should show `active (running)`.

Check that the service is listening on its expected port:

```bash
ss -tlnp | grep <port>
```

Monitor the logs briefly to confirm no new errors appear:

```bash
journalctl -u <service> --no-pager -n 10
```

If the service is client-facing, test it end-to-end (e.g., `curl` for a web service).

## Prevention

- **Validate configuration before reloading** — always run the service's config validation command (e.g., `nginx -t`) before applying changes
- **Use systemd restart policies** — add `Restart=on-failure` and `RestartSec=5` to the unit file so the service retries automatically after a transient failure
- **Enable systemd watchdog** — if the service supports it, configure `WatchdogSec=` so systemd restarts unresponsive services
- **Set up monitoring** — alert on service state changes (`systemctl is-active` checks, Prometheus `node_systemd_unit_state`, or equivalent)
- **Use drop-in overrides** — keep modifications in `/etc/systemd/system/<service>.service.d/` rather than editing vendor unit files directly, so package updates do not overwrite your changes
