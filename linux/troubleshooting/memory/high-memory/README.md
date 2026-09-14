# High Memory Usage

## Problem

The system is running low on available memory, leading to slow performance, application crashes, or OOM (Out of Memory) kills. This can affect individual applications or cause system-wide instability.

## Symptoms

- System feels sluggish or unresponsive
- Applications are killed unexpectedly (OOM killer)
- `free -h` shows very little available memory
- Swap usage is high or constantly increasing
- `dmesg` reports "Out of memory" messages
- Services restart frequently without clear reason

## Troubleshooting

### Step 1 — Check overall memory usage

```bash
free -h
```

Look at the output columns carefully:

- **total** — Total physical RAM installed
- **used** — Memory actively used by processes (this is what matters most)
- **free** — Completely unused memory (often very low on a healthy system, and that is normal)
- **buff/cache** — Memory used by the kernel for filesystem caches and buffers. This memory is **reclaimable** — the kernel will release it when applications need more memory. High buff/cache is not a problem.
- **available** — The best indicator of how much memory is actually available for new processes. This is `free` plus reclaimable `buff/cache`. If available is low, the system is genuinely under memory pressure.

A common mistake is looking at `free` and panicking. Linux intentionally uses spare RAM for caching. Focus on **available** instead.

### Step 2 — Identify the top memory-consuming processes

```bash
ps aux --sort=-%mem | head -20
```

This lists the top 20 processes sorted by memory usage (descending). Check:

- Which process is consuming the most memory?
- Is the usage expected for that application?
- Is any process using a suspiciously large or growing percentage of RAM?

### Step 3 — Monitor memory usage in real time

```bash
top -o %MEM
```

Press `Shift+M` to sort by memory usage. Watch for processes whose memory usage (RES column) keeps growing over time — this may indicate a memory leak.

### Step 4 — Check swap usage

```bash
swapon --show
```

Then:

```bash
free -h | grep -i swap
```

Swap is disk space used as an extension of RAM. Some swap usage is normal under temporary memory pressure. Swap becomes a problem when:

- Swap usage keeps growing continuously
- The system is constantly swapping data in and out (thrashing), which causes severe slowdown
- Swap is fully used alongside low available RAM — the system has no safety net left

### Step 5 — Check memory activity and swapping rate

```bash
vmstat 1 5
```

This shows 5 samples at 1-second intervals. Focus on:

- **si** (swap in) — Pages read from swap to memory per second
- **so** (swap out) — Pages written from memory to swap per second
- If `si` and `so` are consistently non-zero, the system is actively thrashing
- **free** — Available free memory per sample
- **wa** (iowait in the CPU section) — High iowait combined with swap activity confirms memory pressure is causing disk I/O bottlenecks

### Step 6 — Inspect detailed memory information

```bash
cat /proc/meminfo
```

Key fields to check:

- **MemTotal** — Total physical RAM
- **MemAvailable** — Estimated memory available for new applications
- **SwapTotal** — Total swap space configured
- **SwapFree** — Unused swap space
- **Cached** and **Buffers** — Reclaimable memory used for caching
- **Dirty** — Pages waiting to be written to disk (high values may indicate I/O pressure)

### Step 7 — Check if the OOM killer was triggered

```bash
dmesg | grep -i oom
```

And:

```bash
journalctl -k | grep -i "out of memory"
```

If the OOM killer was invoked, you will see messages like:

- `Out of memory: Killed process <PID> (<process_name>)`
- `oom-kill:constraint=...`

Note which process was killed, when it happened, and how much memory it was using. This tells you whether the OOM kill was a one-time event or a recurring problem.

### Step 8 — Check if swap is configured at all

```bash
swapon --show
```

If the output is empty, the system has no swap configured. Without swap, the OOM killer activates sooner under memory pressure, and temporary spikes have no buffer.

## Root Cause

High memory usage typically comes from one of these causes:

1. **Memory leak** — A process allocates memory but never releases it. Memory usage grows steadily over time until the system runs out.
2. **Insufficient RAM** — The workload simply requires more memory than the system has. This is common when services are scaled up without adjusting resources.
3. **Too many processes** — More applications or services are running than the system can support. This includes runaway processes or fork bombs.
4. **No swap configured** — Without swap, there is no buffer for temporary memory spikes. The OOM killer triggers earlier than it would otherwise.
5. **Misconfigured application** — An application is configured with memory limits that exceed available system resources (e.g., JVM heap set too high, database cache too large).

## Resolution

The fix depends on the root cause:

**If a runaway process is consuming memory:**

```bash
# Identify the process
ps aux --sort=-%mem | head -5

# Kill it gracefully first
kill <PID>

# If it does not respond, force kill
kill -9 <PID>
```

**If no swap is configured and the system needs a buffer:**

```bash
# Create a 2 GB swap file (adjust size as needed)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Make it persistent across reboots
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

**If RAM is genuinely insufficient:**

- Add more physical RAM (or increase VM memory allocation)
- Scale the workload across multiple systems
- Reduce the number of running services

**If a memory leak is suspected:**

- Restart the affected service as a temporary fix
- Report the issue to the application vendor or development team
- Monitor the process memory over time to confirm the leak pattern

**If application memory configuration is too aggressive:**

- Reduce application-level memory settings (e.g., JVM `-Xmx`, PostgreSQL `shared_buffers`, Redis `maxmemory`)
- Set limits to leave headroom for the OS and other services

## Verification

After applying the fix:

```bash
# Confirm memory situation improved
free -h

# Verify swap is active and has space
swapon --show

# Check that no new OOM kills occurred
dmesg | grep -i oom

# Monitor for stability over time
vmstat 1 10
```

Available memory should be at a comfortable level. If you killed a runaway process, confirm the service that replaced it is running correctly. If you added swap, confirm it appears in `swapon --show`.

## Automation

A simple monitoring script that alerts when available memory drops below a threshold:

```bash
#!/bin/bash
# monitor_memory.sh — Alert when available memory drops below threshold
#
# Usage: ./monitor_memory.sh
# Configure THRESHOLD_MB to your environment.
# Run via cron: */5 * * * * /path/to/monitor_memory.sh

THRESHOLD_MB=500
LOG_FILE="/var/log/memory_monitor.log"

available_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
available_mb=$((available_kb / 1024))

if [ "$available_mb" -lt "$THRESHOLD_MB" ]; then
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    top_procs=$(ps aux --sort=-%mem | head -4 | tail -3)

    echo "${timestamp} WARNING: Available memory is ${available_mb} MB (threshold: ${THRESHOLD_MB} MB)" >> "$LOG_FILE"
    echo "Top memory consumers:" >> "$LOG_FILE"
    echo "$top_procs" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"

    # Add notification here (email, webhook, etc.)
    # Example: curl -s -X POST https://hooks.example.com/alert -d "{\"text\":\"Low memory: ${available_mb} MB\"}"
fi
```

Make it executable:

```bash
chmod +x monitor_memory.sh
```

Run it via cron every 5 minutes:

```bash
crontab -e
# Add:
# */5 * * * * /path/to/monitor_memory.sh
```

## Prevention

- **Monitoring** — Set up memory monitoring with alerts (the script above, or tools like Prometheus + node_exporter, Zabbix, or Datadog). Alert on available memory and swap usage before problems occur.
- **cgroups / systemd memory limits** — Constrain memory-hungry services so they cannot consume all system RAM. Example with systemd:

```ini
# In a systemd unit override (systemctl edit <service>)
[Service]
MemoryMax=2G
MemoryHigh=1.5G
```

When the service exceeds `MemoryHigh`, the kernel throttles it. At `MemoryMax`, the service is OOM-killed instead of affecting the rest of the system.

- **Swap configuration** — Always configure at least a small swap space as a safety buffer, even on systems with plenty of RAM. It gives the kernel room to move inactive pages out and delays OOM kills during temporary spikes.
- **Capacity planning** — Track memory usage trends over time. If available memory steadily decreases as workload grows, plan to add RAM or distribute services before the system becomes unstable.
- **Application tuning** — Set memory limits in application configuration to prevent any single service from monopolizing RAM. Leave headroom for the OS, kernel caches, and unexpected spikes.
