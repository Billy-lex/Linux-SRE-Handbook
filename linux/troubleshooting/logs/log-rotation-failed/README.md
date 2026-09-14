# Log Rotation Failed

## Problem

logrotate is not rotating logs as expected, causing log files to grow indefinitely and eventually fill the disk. This can lead to service failures, lost log data, and system instability.

## Symptoms

- Log files growing very large (hundreds of MB or several GB)
- Disk space running low due to unrotated logs
- logrotate reports errors when run manually or via cron
- Old rotated logs (`.gz`, `.1`, `.2`) not being cleaned up
- Applications fail because `/var/log` or the relevant partition is full
- logrotate status file shows rotation dates far in the past

## Troubleshooting

### Step 1 — Check logrotate status

```bash
cat /var/lib/logrotate/logrotate.status
```

On some distributions the status file is at a different location:

```bash
cat /var/lib/logrotate.status
```

This file records the last rotation date for each log file. Look for entries where the date is significantly older than expected given the rotation frequency. If a log is configured for `daily` rotation but the status shows it was last rotated weeks ago, something is preventing rotation.

### Step 2 — Test the configuration in debug mode

```bash
logrotate -d /etc/logrotate.d/<config-file>
```

The `-d` flag enables debug mode: logrotate parses the configuration and reports what it *would* do, without actually rotating anything. Look for syntax errors, wrong file paths, or unexpected behavior in the output.

To test the entire configuration:

```bash
logrotate -d /etc/logrotate.conf
```

### Step 3 — Run logrotate manually in verbose mode

```bash
logrotate -vf /etc/logrotate.conf
```

The `-v` flag produces verbose output showing each action logrotate takes. The `-f` flag forces rotation even if the log does not meet the normal size or time criteria. This confirms whether logrotate can actually perform rotation when invoked directly.

If this works but automatic rotation is not happening, the problem is likely with the cron job or timer that triggers logrotate.

### Step 4 — Check the logrotate configuration syntax

Look for common configuration errors in `/etc/logrotate.d/` files:

```bash
ls -l /etc/logrotate.d/
```

Common syntax problems:

- Missing closing brace `}`
- Missing `endscript` after a `postrotate` or `prerotate` block
- Wrong log file path (file does not exist and `missingok` is not set)
- Invalid directive names or values
- Conflicting options (e.g., both `compress` and `nocompress` in the same block)

Review the main configuration file as well:

```bash
cat /etc/logrotate.conf
```

### Step 5 — Check if the logrotate cron job exists and is running

logrotate is typically triggered by a cron job or systemd timer.

Check for the cron job:

```bash
cat /etc/cron.daily/logrotate
```

Check for additional cron-based triggers:

```bash
ls -l /etc/cron.d/ | grep logrotate
```

Check if a systemd timer is used instead:

```bash
systemctl list-timers | grep logrotate
```

Verify that cron itself is running:

```bash
systemctl status crond
```

On Debian/Ubuntu systems the service name is `cron`:

```bash
systemctl status cron
```

If cron is not running or the logrotate cron job is missing, logrotate will never run automatically.

### Step 6 — Check if a process is holding the log file open

Some applications keep their log files open continuously. When logrotate renames the file during rotation, the application continues writing to the renamed file descriptor instead of the new log file.

```bash
lsof /path/to/large.log
```

If a process has the file open, logrotate needs either:

- A `postrotate` script that signals the application to reopen its log files (e.g., `kill -HUP <pid>`), or
- The `copytruncate` directive, which copies the log content to a new file and truncates the original in place, so the application can keep writing to the same file descriptor.

### Step 7 — Check permissions on the log file and directory

logrotate runs as root, but check that the log file and its parent directory have appropriate permissions:

```bash
ls -la /var/log/<log-directory>/
```

If logrotate is configured with a `su` directive (e.g., `su user group`), verify that the specified user and group have write access to the directory:

```bash
ls -ld /var/log/<log-directory>/
```

A permissions mismatch between the `su` directive and the actual directory ownership will cause logrotate to skip rotation with an error.

### Step 8 — Check if SELinux is blocking logrotate

On systems with SELinux enforcing:

```bash
getenforce
```

If SELinux is `Enforcing`, check the audit log for denials related to logrotate:

```bash
grep logrotate /var/log/audit/audit.log | grep denied
```

If denials are found, use `audit2allow` to generate a policy module:

```bash
grep logrotate /var/log/audit/audit.log | audit2allow -M logrotate-fix
semodule -i logrotate-fix.pp
```

Only apply SELinux policy changes after reviewing what the generated module permits.

## Root Cause

Common root causes of log rotation failure:

1. **logrotate cron job not running** — The cron service is stopped, the `/etc/cron.daily/logrotate` script was removed, or the systemd timer is disabled.
2. **Syntax error in configuration file** — A missing brace, missing `endscript`, or invalid directive prevents logrotate from parsing the configuration.
3. **Log file held open by a process** — The application keeps the log file open and does not reopen it after rotation, so it continues writing to the old (renamed) file.
4. **Wrong permissions** — The log file or directory permissions do not match what logrotate expects, especially when a `su` directive is used.
5. **logrotate not installed** — On minimal or custom installations, logrotate may not be present at all.

## Resolution

### Fix the cron job or timer

If cron is not running:

```bash
systemctl enable --now crond
```

If the logrotate cron job was removed, reinstall the logrotate package to restore it:

```bash
# RHEL/CentOS
dnf reinstall logrotate

# Debian/Ubuntu
apt-get install --reinstall logrotate
```

### Fix configuration syntax errors

Edit the problematic file in `/etc/logrotate.d/` and correct the syntax. After fixing, verify with debug mode:

```bash
logrotate -d /etc/logrotate.d/<config-file>
```

### Handle files held open by processes

For applications that support reopening log files on signal, add a `postrotate` script:

```text
/var/log/myapp/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    postrotate
        systemctl reload myapp > /dev/null 2>&1 || true
    endscript
}
```

For applications that cannot reopen log files on signal, use `copytruncate`:

```text
/var/log/myapp/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
```

Note: `copytruncate` has a small window where log entries written between the copy and the truncate may be lost. Prefer `postrotate` with a reload signal when possible.

### Fix permissions

Adjust the log file or directory permissions to match the logrotate configuration:

```bash
chown root:root /var/log/myapp/
chmod 0755 /var/log/myapp/
```

Or adjust the `su` directive in the logrotate config to match the actual ownership:

```text
/var/log/myapp/*.log {
    su myapp myapp
    daily
    rotate 7
    compress
    missingok
    notifempty
}
```

### Example: A complete logrotate configuration

```text
/var/log/myapp/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 myapp myapp
    sharedscripts
    postrotate
        systemctl reload myapp > /dev/null 2>&1 || true
    endscript
}
```

Common options explained:

- `daily` — Rotate every day (alternatives: `weekly`, `monthly`, `size <size>`)
- `rotate 14` — Keep 14 rotated log files before deleting the oldest
- `compress` — Compress rotated logs with gzip
- `delaycompress` — Delay compression by one rotation cycle (useful when a process may still write to the just-rotated file)
- `missingok` — Do not error if the log file is missing
- `notifempty` — Do not rotate if the log file is empty
- `create <mode> <owner> <group>` — Create the new log file with the specified permissions and ownership
- `sharedscripts` — Run the `postrotate` script only once for all matched log files
- `postrotate` / `endscript` — Commands to run after rotation (e.g., reload the service)

## Verification

After applying fixes, confirm logrotate can parse and execute the configuration:

```bash
logrotate -d /etc/logrotate.conf
```

Debug mode should complete without errors for all configured log files.

Force a manual rotation to confirm it works end to end:

```bash
logrotate -vf /etc/logrotate.conf
```

Verify that rotated files were created:

```bash
ls -lh /var/log/myapp/
```

Check the status file to confirm the rotation date was updated:

```bash
cat /var/lib/logrotate/logrotate.status | grep myapp
```

Confirm that the application is still writing to the new log file:

```bash
tail -f /var/log/myapp/current.log
```

Verify the cron job or timer is scheduled for the next run:

```bash
systemctl list-timers | grep logrotate
```

## Prevention

- **Monitor log file sizes** — Set up alerts for log files that exceed a reasonable threshold. A simple check:

  ```bash
  find /var/log -type f -size +100M -exec ls -lh {} \;
  ```

- **Test new configurations with debug mode** — Always run `logrotate -d /etc/logrotate.d/<config>` after adding or modifying a logrotate configuration, before relying on automatic rotation.

- **Include logrotate in regular maintenance** — Periodically review `/var/lib/logrotate/logrotate.status` to confirm all configured logs are being rotated on schedule.

- **Use separate partitions for /var/log** — Isolating log files on their own partition prevents unrotated logs from affecting the rest of the system.

- **Limit journal size** — Configure `SystemMaxUse` in `/etc/systemd/journald.conf` to cap the systemd journal independently of logrotate.
