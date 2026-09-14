# Disk Full

## Problem

A filesystem has run out of available disk space. Applications cannot write data, logs cannot be recorded, and in severe cases the system may become unstable or services may crash.

## Symptoms

- Applications fail with "No space left on device" errors
- Services crash or refuse to start
- Log entries stop appearing (logging daemon cannot write)
- Database writes fail
- System feels sluggish or unresponsive
- `df -h` shows a filesystem at 100% usage

## Troubleshooting

### Step 1 — Identify which filesystem is full

```bash
df -h
```

This shows all mounted filesystems with human-readable sizes. Look for any filesystem where `Use%` is at or near 100%. Note the mount point — that is where you need to focus your cleanup.

If the output is long, filter for high-usage filesystems:

```bash
df -h | awk 'NR==1 || +$5 > 80'
```

### Step 2 — Find which directories consume the most space

```bash
du -sh /* 2>/dev/null | sort -rh | head -10
```

This reports the total size of each top-level directory, sorted largest first. Replace `/*` with a more specific path (e.g., `/var/*`) to drill down into the problematic mount point.

Continue narrowing down:

```bash
du -sh /var/* 2>/dev/null | sort -rh | head -10
```

```bash
du -sh /var/log/* 2>/dev/null | sort -rh | head -10
```

### Step 3 — Locate individual large files

```bash
find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null
```

This finds all files larger than 100 MB anywhere on the system and displays their size and path. Adjust the size threshold (`+500M`, `+1G`) as needed.

### Step 4 — Check for deleted files still held open by processes

A file that has been deleted from the filesystem but is still open by a running process continues to occupy disk space. This is a common cause of "disk full" situations where `du` does not account for the used space.

```bash
lsof +L1
```

This lists open files that have been unlinked (deleted). The `SIZE` column shows how much space each file is still consuming. If a large file appears here, restarting or signaling the process that holds it open will free the space.

To identify the specific process holding the largest deleted file:

```bash
lsof +L1 | awk '{print $2, $7, $9}' | sort -k2 -rn | head -5
```

### Step 5 — Check /var/log for oversized log files

Log files are among the most common culprits.

```bash
ls -lhS /var/log/ | head -20
```

Check for individual large log files:

```bash
find /var/log -type f -size +50M -exec ls -lh {} \;
```

Check whether logrotate is configured and running:

```bash
cat /etc/logrotate.conf
```

```bash
ls -l /etc/logrotate.d/
```

```bash
cat /var/lib/logrotate/logrotate.status
```

The status file shows when each log was last rotated. If rotation has not run recently, that is likely part of the problem.

### Step 6 — Check for old temporary and cache files

```bash
du -sh /tmp /var/tmp /var/cache 2>/dev/null
```

Package manager caches can grow large over time:

```bash
du -sh /var/cache/dnf /var/cache/yum /var/cache/apt 2>/dev/null
```

## Root Cause

Common root causes of a full disk:

1. **Log files not rotated** — Application or system logs grew without bound because logrotate was not configured or not running.
2. **Application writing excessive data** — A misbehaving application is producing large output files, core dumps, or debug logs.
3. **No disk space monitoring** — There are no alerts configured to warn when disk usage crosses a threshold, so the problem is only discovered when services fail.
4. **Old files not cleaned up** — Accumulated backups, old log archives, temporary files, or package caches were never purged.
5. **Deleted files still held open** — A process holds a reference to a large deleted file, preventing the space from being reclaimed.

## Resolution

### Clean up log files safely

If a process is actively writing to a log file, truncate it rather than deleting it. Deleting the file while the process holds it open does not free the space until the process is restarted.

```bash
# Truncate a log file without breaking the writing process
truncate -s 0 /var/log/large-file.log
```

For files that are not actively in use, normal deletion is fine:

```bash
rm /var/log/old-rotated-log.gz
```

### Remove old and unnecessary files

```bash
# Clean package manager cache (RHEL/CentOS)
dnf clean all
```

```bash
# Clean package manager cache (Debian/Ubuntu)
apt-get clean
```

```bash
# Remove old journal logs, keeping only the last 7 days
journalctl --vacuum-time=7d
```

### Release space from deleted-but-open files

Restart the process holding the deleted file open:

```bash
systemctl restart <service-name>
```

Or signal the process to reopen its file descriptors if it supports that:

```bash
kill -HUP <PID>
```

### Expand the disk if cleanup is insufficient

If the filesystem is legitimately too small for the workload, expand the underlying storage. This is environment-specific (LVM extend, cloud volume resize, etc.) and should be planned as a capacity management task.

### Configure logrotate to prevent recurrence

Ensure logrotate is configured for all significant log sources:

```bash
# Example: /etc/logrotate.d/myapp
/var/log/myapp/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 myapp myapp
}
```

Test the configuration:

```bash
logrotate -d /etc/logrotate.d/myapp
```

## Verification

After applying fixes, confirm the filesystem has free space:

```bash
df -h
```

Confirm the target filesystem usage has dropped below your alert threshold (e.g., 80%).

If you truncated a log file, verify the service is still running and writing logs normally:

```bash
systemctl status <service-name>
```

If you restarted a service to release a deleted-but-open file, confirm no large unlinked files remain:

```bash
lsof +L1
```

Run logrotate in debug mode to confirm the configuration is valid:

```bash
logrotate -d /etc/logrotate.conf
```

## Automation

A simple monitoring script can detect disk space problems before they cause service failures.

See `check_disk.sh` in this directory. It checks all mounted filesystems and prints a warning when usage exceeds a configurable threshold (default: 80%).

Usage:

```bash
chmod +x check_disk.sh
./check_disk.sh
./check_disk.sh 90    # alert at 90% instead of 80%
```

Run it periodically via cron:

```bash
# Check every 15 minutes
*/15 * * * * /path/to/check_disk.sh 80 | logger -t disk-check
```

For production environments, integrate disk usage checks into your monitoring system (Prometheus node_exporter, Zabbix, Nagios, etc.) rather than relying on a standalone script.

## Prevention

- **Configure logrotate** for all services that write log files. Set appropriate rotation frequency, retention count, and compression.
- **Set up disk space monitoring and alerts** at multiple thresholds (e.g., warning at 80%, critical at 90%) so you can act before the disk is full.
- **Schedule periodic cleanup** of temporary files, package caches, and old backups using cron or systemd timers.
- **Practice capacity planning** — track disk usage trends over time and provision additional storage before it becomes urgent.
- **Use separate partitions or volumes** for high-write directories (`/var/log`, `/tmp`, database data directories) so that one filling up does not affect the entire system.
- **Limit journal size** by configuring `SystemMaxUse` in `/etc/systemd/journald.conf`.
