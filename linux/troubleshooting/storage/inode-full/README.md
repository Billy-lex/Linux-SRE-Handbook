# Inode Exhaustion

## Problem

The filesystem has run out of inodes. You cannot create new files even though `df -h` shows plenty of free disk space. This happens because every file, directory, and symbolic link on a Linux filesystem requires an inode, and the total number of inodes is fixed when the filesystem is created.

## Symptoms

- "No space left on device" error when creating or saving files
- `df -h` shows free disk space available
- Applications fail to write logs, temporary files, or session data
- Mail delivery fails
- Services crash or refuse to start because they cannot create PID files or lock files

## Troubleshooting

### Step 1: Confirm inode exhaustion

```bash
df -i
```

Look at the `IUse%` column. A value of `100%` (or near it) confirms that inodes are exhausted. Compare this with `df -h` — if disk space is available but inodes are full, the problem is too many small files, not large files.

### Step 2: Identify which mountpoint is affected

```bash
df -i /path/to/failed/write
```

This tells you which filesystem is out of inodes. The problem may be on `/`, `/var`, `/tmp`, or any separate mount.

### Step 3: Find the directories with the most files

```bash
find /mountpoint -xdev -printf '%h\n' | sort | uniq -c | sort -rn | head -20
```

The `-xdev` flag ensures `find` stays on the affected filesystem and does not descend into other mounts. The output shows the directories containing the largest number of entries.

This command may take a long time on large filesystems. If the system is under heavy I/O pressure, run it with reduced priority:

```bash
ionice -c 3 nice -n 19 find /mountpoint -xdev -printf '%h\n' | sort | uniq -c | sort -rn | head -20
```

### Step 4: Investigate common culprits

The directories identified in Step 3 typically fall into a few known categories:

**Mail queue buildup:**

```bash
ls /var/spool/postfix/maildrop/ | wc -l
```

When cron jobs generate output and no mail transfer agent is configured to deliver it, each message creates a file in the maildrop directory. Over time this can grow to millions of files.

**PHP/application session files:**

```bash
ls /var/lib/php/sessions/ | wc -l
find /tmp -maxdepth 1 -name 'sess_*' 2>/dev/null | wc -l
```

If session garbage collection is misconfigured or disabled, session files accumulate indefinitely.

**Cache or temporary files:**

```bash
find /var/cache -xdev -type f | wc -l
find /tmp -xdev -type f | wc -l
```

Application caches, old temporary files, and log rotation artifacts can produce millions of small files.

**Spool and printer queues:**

```bash
ls /var/spool/cups/ | wc -l
```

### Step 5: Count total inodes on the affected filesystem

```bash
find /mountpoint -xdev | wc -l
```

This gives a total count of all files, directories, and links on the filesystem. Compare this with the total inode count from `df -i` to understand how close you are to the limit.

## Root Cause

The filesystem was formatted with a fixed number of inodes, and the system accumulated more files than inodes available. Common causes:

- **Mail queue buildup** — cron jobs producing output with no configured MTA, each message stored as a separate file in `/var/spool/postfix/maildrop/`
- **Session file accumulation** — PHP or application sessions not being garbage-collected
- **Cache directories** — application caches creating millions of small files without cleanup
- **Temporary files** — scripts or applications writing to `/tmp` or `/var/tmp` without removing old entries
- **Log or spool artifacts** — log rotation misconfiguration, CUPS spool files, or similar

The key insight is that disk space and inodes are independent resources. A filesystem can exhaust inodes while having gigabytes of free space, because the limiting factor is the number of files, not their size.

## Resolution

### Remove the identified small files

Once you have identified the directory responsible, remove the files. For directories with millions of files, `rm *` will fail with "Argument list too long". Use `find` instead:

```bash
find /var/spool/postfix/maildrop/ -type f -delete
```

For session files that are older than the session lifetime:

```bash
find /var/lib/php/sessions/ -type f -mmin +1440 -delete
```

Adjust the `-mmin` value to match your application's session timeout (1440 minutes = 24 hours).

For cache or temporary files:

```bash
find /var/cache/appname/ -type f -mtime +7 -delete
```

### Configure cleanup to prevent recurrence

**Mail queue:** If cron output is not needed, redirect it to `/dev/null` in the crontab:

```
*/5 * * * * /path/to/script.sh > /dev/null 2>&1
```

Alternatively, set `MAILTO=""` at the top of the crontab to suppress mail entirely:

```
MAILTO=""
*/5 * * * * /path/to/script.sh
```

**Session files:** Verify that PHP session garbage collection is configured:

```bash
grep -E 'session.gc_probability|session.gc_maxlifetime' /etc/php.ini
```

Or create a systemd timer or cron job to clean old sessions:

```bash
# /etc/cron.d/php-session-cleanup
0 */6 * * * root find /var/lib/php/sessions/ -type f -mmin +1440 -delete
```

**Cache files:** Configure the application's cache TTL, or add a cron job to remove old entries.

## Verification

Confirm that inodes are now available:

```bash
df -i
```

The `IUse%` value should have dropped significantly.

Confirm that you can create new files:

```bash
touch /mountpoint/test_file && rm /mountpoint/test_file
```

Confirm that affected services are functioning:

```bash
systemctl status postfix
systemctl status php-fpm
```

Check that the cleanup mechanism is in place and scheduled:

```bash
crontab -l
systemctl list-timers
```

Monitor over the next few hours to confirm inode usage is stable and not climbing again.

## Prevention

- Monitor inode usage alongside disk space — set alerts at 80% and 90% inode usage, not just disk space usage
- Include `df -i` in regular health checks, not just `df -h`
- Configure cron job output redirection (`> /dev/null 2>&1` or `MAILTO=""`) on systems where mail delivery is not needed
- Verify session garbage collection is active for any web application framework
- Set up automated cleanup jobs for known accumulation points (maildrop, sessions, cache directories)
- When creating new filesystems for workloads that produce many small files, consider increasing the inode ratio at format time with `mkfs.ext4 -i <bytes-per-inode>`
