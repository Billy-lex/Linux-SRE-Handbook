# High CPU Usage

## Problem

The system is experiencing high CPU usage, causing slow response times, application timeouts, or degraded user experience.

## Symptoms

- System feels sluggish or unresponsive
- Applications respond slowly
- `top` or `htop` shows CPU usage near 100%
- Load average is significantly higher than the number of CPU cores
- Users report timeouts or slow page loads

## Troubleshooting

### Step 1: Identify which processes are consuming CPU

```bash
top -b -n 1 -o %CPU | head -20
```

This gives a snapshot of the top CPU-consuming processes sorted by CPU usage. Look for the `%CPU` column and the `COMMAND` column.

### Step 2: Get a more detailed view of a specific process

```bash
top -p <PID>
```

Watch whether the CPU usage is sustained or spiking. Note whether it is in user space (`us`) or system/kernel space (`sy`).

### Step 3: Check the overall CPU breakdown

```bash
mpstat -P ALL 1 3
```

This shows per-core CPU usage over 3 one-second intervals. Look for:
- `%usr` — user-space CPU
- `%sys` — kernel-space CPU
- `%iowait` — waiting on I/O (high iowait suggests disk bottleneck, not true CPU pressure)
- `%idle` — available CPU

### Step 4: Check system load average

```bash
uptime
```

Compare the load average to the number of CPU cores:

```bash
nproc
```

A load average higher than the core count indicates the system is overloaded.

### Step 5: Identify threads within a process

```bash
top -H -p <PID>
```

This shows individual threads. Useful when a multi-threaded application has one runaway thread.

### Step 6: Check if the process is in an uninterruptible state

```bash
ps aux | awk '$8 ~ /D/ {print}'
```

Processes in `D` state (uninterruptible sleep) are usually waiting on I/O and cannot be killed. They contribute to load average but not directly to CPU usage.

### Step 7: Check for recent changes

```bash
journalctl --since "1 hour ago" -p warning
```

Look for application errors, OOM events, or service restarts that correlate with the CPU spike.

## Root Cause

Common root causes include:

- **Application bug** — infinite loop, inefficient query, memory leak causing excessive garbage collection
- **Runaway process** — a script or job consuming resources without bounds
- **Traffic spike** — legitimate or malicious increase in requests
- **I/O wait misread** — high `%iowait` looks like CPU pressure but the bottleneck is disk
- **Kernel or driver issue** — rare, but high `%sys` can indicate a kernel-level problem

## Resolution

The fix depends on the root cause identified:

**Runaway process:**

```bash
kill <PID>
```

If the process does not respond:

```bash
kill -9 <PID>
```

**Application-level issue:** Restart the service and investigate the application logs.

**Traffic spike:** Scale resources or investigate the source of the traffic.

**I/O wait:** Investigate disk performance (see `storage/disk-full` or filesystem cases).

## Verification

After applying the fix:

```bash
top -b -n 1 -o %CPU | head -10
```

Confirm CPU usage has dropped and load average is declining:

```bash
uptime
```

Monitor for a few minutes to ensure the problem does not return.

## Automation

A simple script to alert when CPU usage exceeds a threshold:

```bash
#!/bin/bash
# check_cpu.sh - Alert when CPU usage exceeds threshold

THRESHOLD=90
INTERVAL=5

while true; do
  usage=$(top -b -n 1 | grep "Cpu(s)" | awk '{print $2 + $4}')
  load=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)

  if (( $(echo "$usage > $THRESHOLD" | bc -l) )); then
    echo "[ALERT] CPU usage: ${usage}% | Load: ${load}"
    top -b -n 1 -o %CPU | head -6
  fi

  sleep $INTERVAL
done
```

Usage:

```bash
bash check_cpu.sh
```

## Prevention

- Set up monitoring (Prometheus + Grafana, Zabbix, or CloudWatch) to track CPU trends
- Configure alerts for sustained high CPU (not just momentary spikes)
- Use `cgroups` or `systemd` resource limits to cap per-service CPU
- Perform capacity planning based on historical CPU usage patterns
- Load test applications before deployment to understand their CPU profile
