# Disk I/O Bottleneck

## Problem

The system is responding slowly, and the bottleneck is disk I/O — the disk cannot keep up with read/write demands. Applications hang, queries time out, and the system feels unresponsive even though CPU and memory appear fine.

## Symptoms

- System feels sluggish despite low CPU usage
- `top` shows high `%wa` (iowait) — CPU cores are idle, waiting for disk
- Load average is high, but CPU usage is low
- Disk activity LED is constantly on (physical servers)
- Applications time out or respond very slowly
- Commands like `ls` or `cd` take several seconds

## Troubleshooting

### Step 1 — Rule out CPU and memory as the bottleneck

Before investigating disk I/O, confirm that CPU and memory are not the real problem.

```bash
top -b -n 1 | head -5
```

Look at the third line (`%Cpu(s)`):

- If `%id` (idle) is high but `%wa` (iowait) is also high, the CPU is waiting on disk — I/O is likely the bottleneck.
- If `%us` or `%sy` is high, the problem is CPU-bound, not I/O-bound. Investigate CPU first (see `cpu/high-cpu`).

Check memory:

```bash
free -h
```

If available memory is very low and swap is heavily used, the I/O pressure might be caused by swap thrashing rather than application disk access. In that case, investigate memory first (see `memory/high-memory`).

### Step 2 — Confirm disk I/O is the bottleneck with iostat

```bash
iostat -xz 1 5
```

This reports extended disk statistics every 1 second for 5 samples. Focus on these columns:

| Column | What it means | Normal range |
|--------|--------------|--------------|
| `%util` | Percentage of time the disk was busy | < 70% healthy, > 90% saturated |
| `await` | Average time (ms) for an I/O request to complete | < 10ms HDD, < 1ms SSD |
| `r/s`, `w/s` | Read and write operations per second | Depends on disk type |
| `rMB/s`, `wMB/s` | Read and write throughput | Should not exceed disk bandwidth |
| `avgqu-sz` | Average queue length of I/O requests | < 2–3 is normal |
| `avgrq-sz` | Average request size in sectors | Helps identify sequential vs random I/O |

Key indicators of I/O saturation:

- `%util` consistently above 90% — the disk is fully busy
- `await` much higher than normal (e.g., > 100ms on HDD, > 10ms on SSD) — requests are queuing up
- `avgqu-sz` growing — more requests are waiting than the disk can handle

If `iostat` is not installed:

```bash
# RHEL/CentOS
dnf install sysstat

# Debian/Ubuntu
apt-get install sysstat
```

### Step 3 — Check I/O wait and blocked processes with vmstat

```bash
vmstat 1 5
```

Focus on:

- **b** (blocked processes) — processes waiting for I/O. A consistently high number confirms I/O pressure.
- **wa** (iowait percentage) — matches what `top` reported. Sustained values above 10–20% indicate disk is the bottleneck.
- **bi** (blocks received / read from disk) and **bo** (blocks sent / written to disk) — shows I/O volume per second.
- **si** / **so** (swap in / swap out) — if non-zero, the system is actively swapping. High swap activity can look like disk I/O pressure but the root cause is memory (see `memory/high-memory`).

### Step 4 — Identify which process is doing the I/O

This is the key step — finding the specific process responsible.

**Method 1: iotop (recommended)**

```bash
iotop -o
```

The `-o` flag shows only processes that are currently doing I/O. This immediately reveals the top I/O consumers. Watch for:

- **DISK READ** and **DISK WRITE** columns — current throughput per process
- **IO>** column — percentage of time the process is waiting on I/O
- **COMMAND** — which process it is

To capture a snapshot without interactive mode:

```bash
iotop -b -o -n 3
```

This runs 3 iterations in batch mode, useful for logging.

If `iotop` is not installed:

```bash
# RHEL/CentOS
dnf install iotop

# Debian/Ubuntu
apt-get install iotop
```

**Method 2: pidstat (if iotop is unavailable)**

```bash
pidstat -d 1 5
```

This reports per-process I/O statistics every second for 5 samples. Key columns:

- **kB_rd/s** — read rate per process
- **kB_wr/s** — write rate per process
- **kB_ccwr/s** — cancelled write rate (when a task truncates a file before writes complete)

Look for the process with the highest combined read and write rate.

**Method 3: /proc filesystem (if no tools are available)**

```bash
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
    if [ -r /proc/$pid/io ]; then
        read_bytes=$(awk '/read_bytes/ {print $2}' /proc/$pid/io 2>/dev/null)
        write_bytes=$(awk '/write_bytes/ {print $2}' /proc/$pid/io 2>/dev/null)
        if [ -n "$read_bytes" ] || [ -n "$write_bytes" ]; then
            echo "PID: $pid  read: ${read_bytes:-0}  write: ${write_bytes:-0}  cmd: $(cat /proc/$pid/comm 2>/dev/null)"
        fi
    fi
done | sort -t: -k3 -rn | head -20
```

This reads cumulative I/O bytes from `/proc/<pid>/io` for each process and sorts by read volume. Run it twice with a few seconds apart and compare the differences to see which process is actively doing I/O right now.

### Step 5 — Inspect what the offending process is doing

Once you have identified the PID, investigate further:

```bash
# What files does this process have open?
ls -l /proc/<PID>/fd 2>/dev/null | head -30
```

This shows which files the process is reading or writing. Combined with the process name and command line, it reveals what kind of I/O is happening:

```bash
cat /proc/<PID>/cmdline | tr '\0' ' '
```

Common patterns:

- **Database process** (mysqld, postgres) with many open data files — likely a query doing full table scans or large writes
- **Application process** writing to log files — excessive logging or debug mode left on
- **Backup or sync tool** (rsync, tar, dd) — expected bulk I/O, but running at the wrong time
- **Compiler or build tool** (gcc, npm, make) — large number of small file reads/writes
- **Unknown process** — check if it is legitimate or suspicious

### Step 6 — Check filesystem-level I/O with dstat

```bash
dstat -d 1 5
```

This shows aggregate disk read/write throughput across all devices. Useful to confirm whether the I/O is concentrated on one disk or spread across multiple.

For per-device breakdown:

```bash
dstat -D sda,sdb -d 1 5
```

Replace `sda`, `sdb` with actual device names from:

```bash
lsblk
```

### Step 7 — Check I/O scheduler and disk type

The I/O scheduler affects how disk requests are ordered and merged. The wrong scheduler for your workload can amplify I/O problems.

```bash
cat /sys/block/sda/queue/scheduler
```

Common schedulers:

- **mq-deadline** — good general-purpose scheduler for SSDs and modern storage
- **bfq** — fair queuing, good for interactive desktops but can add overhead on servers
- **none** / **noop** — no reordering, best for NVMe SSDs or hardware RAID with its own cache

For rotational disks (HDD), `mq-deadline` or `bfq` is usually better. For SSDs and NVMe, `none` or `mq-deadline` is preferred.

Check whether the disk is rotational:

```bash
cat /sys/block/sda/queue/rotational
```

Returns `1` for HDD, `0` for SSD.

## Root Cause

Once the offending process is identified, common root causes include:

- **Inefficient database query** — missing index causes full table scan, generating massive random reads
- **Excessive logging** — application writes verbose logs to disk on every request
- **Swap thrashing** — memory pressure forces constant page swaps to disk (investigate memory, not disk)
- **Bulk operation at peak hours** — backup, log rotation, or ETL job running during high-traffic period
- **Many small random writes** — build systems, package managers, or file sync tools doing thousands of small I/O operations
- **Insufficient disk IOPS** — the workload simply exceeds what the disk can handle (common with HDDs or undersized cloud volumes)
- **Filesystem fragmentation** — heavily fragmented files on ext4 or XFS increase seek time

## Resolution

The fix depends on the root cause identified:

**Inefficient database query:**

Check the slow query log to find the offending query:

```bash
# MySQL
mysqldumpslow -s t /var/log/mysql/slow.log | head -20

# PostgreSQL — enable log_min_duration_statement in postgresql.conf
```

Then use `EXPLAIN` to check the query plan. If the query is doing a full table scan, add the missing index:

```sql
-- MySQL
EXPLAIN SELECT * FROM orders WHERE customer_id = 123;
ALTER TABLE orders ADD INDEX idx_customer_id (customer_id);

-- PostgreSQL
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 123;
CREATE INDEX idx_customer_id ON orders (customer_id);
```

**Excessive logging:**

Reduce the application log level from `DEBUG` or `TRACE` to `INFO` or `WARN`. If log writes must stay verbose, buffer them to reduce disk syncs:

```bash
# Check current log file growth rate
ls -lh /var/log/myapp/*.log
du -sh /var/log/myapp/
```

Ensure logrotate is configured to prevent uncontrolled growth (see `logs/log-rotation-failed`).

**Swap thrashing:**

The I/O pressure is a symptom — the root cause is memory. Investigate memory pressure first (see `memory/high-memory`). Fixing memory will resolve the disk I/O automatically.

**Bulk operation at peak hours:**

Use `ionice` to lower the I/O priority of the batch job, or reschedule it to off-peak hours:

```bash
# Run backup at lowest I/O priority (idle class)
ionice -c 3 rsync -av /data/ /backup/

# Or reschedule with cron to run at 2 AM
echo "0 2 * * * root /usr/local/bin/backup.sh" >> /etc/cron.d/backup
```

**Many small random writes:**

If the workload involves build tools or package managers, use `tmpfs` to move the work to memory:

```bash
# Mount a tmpfs for build output
mount -t tmpfs -o size=2G tmpfs /tmp/build

# Or set TMPDIR for npm/make
export TMPDIR=/tmp/build
```

For applications doing many small writes, batch writes or use a write buffer instead of syncing on every operation.

**Insufficient disk IOPS:**

When the workload genuinely exceeds the disk's capability:

- Upgrade from HDD to SSD
- Increase cloud volume size (cloud providers typically scale IOPS with volume size)
- Add a caching layer (e.g., Redis, memcached) to reduce repeated disk reads
- Distribute I/O across multiple disks or use RAID 0/10

**Filesystem fragmentation:**

Check fragmentation level and defragment if needed:

```bash
# ext4 — check fragmentation
e4defrag -c /path/to/data

# ext4 — defragment (can run on mounted filesystem)
e4defrag /path/to/data

# XFS — defragment
xfs_fsr /path/to/data
```

On XFS, fragmentation is less common but can occur with large files that are frequently modified.

## Automation

A monitoring script that checks disk I/O saturation and captures diagnostic data when thresholds are exceeded:

```bash
# Default thresholds: util 90%, await 50ms
./check_io.sh

# Custom thresholds
./check_io.sh 80 30
```

Run via cron every 5 minutes:

```bash
crontab -e
# Add:
# */5 * * * * /path/to/check_io.sh >> /var/log/io_monitor.log 2>&1
```

The script exits with code 0 when all devices are healthy and code 1 when any device exceeds thresholds, making it suitable for external monitoring integrations (Nagios, Prometheus blackbox, etc.).

## Verification

After applying the fix, confirm that disk I/O has returned to normal levels:

```bash
# Check disk utilization and latency
iostat -xz 1 5
```

`%util` should drop below 70%, and `await` should return to normal range (< 10ms for HDD, < 1ms for SSD).

```bash
# Confirm the offending process is no longer dominating I/O
iotop -o
```

```bash
# Verify no new swap activity
vmstat 1 5
```

The `si` and `so` columns should be zero, and `wa` should be low.
