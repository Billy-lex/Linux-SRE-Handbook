# Zombie Processes

## Problem

Processes are stuck in the `Z` (zombie/defunct) state, indicating that they have finished execution but their parent process has not yet collected their exit status via `wait()` or `waitpid()`. A small number of short-lived zombies is normal, but a growing count signals a problem with the parent process.

## Symptoms

- `ps` shows processes with state `Z` and `<defunct>` in the command name
- Zombie count grows over time instead of staying stable
- A specific parent process is responsible for most or all zombies
- In extreme cases, the system runs out of available PIDs

## Troubleshooting

### Step 1: List all zombie processes

```bash
ps aux | awk '$8 ~ /Z/ {print}'
```

This filters the process list to show only entries in the `Z` state. The command column will typically show the process name wrapped in brackets with `<defunct>`.

### Step 2: Get zombie PID and parent PID (PPID)

```bash
ps -eo pid,ppid,stat,comm | grep Z
```

Each zombie entry shows its own PID and the PPID of the process that created it. The PPID is the key to identifying which process is failing to reap its children.

### Step 3: Identify the parent process

```bash
ps -p <PPID> -o pid,comm,args
```

Replace `<PPID>` with the parent PID from Step 2. This tells you which application or service is responsible for the zombie.

### Step 4: Check if the parent is init/systemd (PID 1)

If the PPID is `1`, the zombie's original parent has already exited and the zombie has been reparented to `init` (systemd). In this case, systemd will eventually reap it. A zombie stuck under PID 1 for a long time may indicate a kernel-level issue, but this is rare.

### Step 5: Count total zombies

```bash
ps aux | awk '$8=="Z"' | wc -l
```

A stable, small count (1–3) is usually harmless. A growing count indicates an active problem with the parent process.

### Step 6: Monitor over time

Run the count command periodically to determine whether zombies are accumulating or staying stable:

```bash
watch -n 5 'ps aux | awk '\''$8=="Z"'\'' | wc -l'
```

If the count keeps increasing, the parent process is consistently failing to reap children.

### Step 7: Trace the parent process behavior

If the parent process is suspected of not calling `wait()`, you can attach `strace` to confirm:

```bash
strace -p <parent-pid> -e trace=wait4,waitid,waitpid
```

This shows whether the parent is making any `wait`-family system calls. If no `wait` calls appear while children are exiting, the parent has a bug in its child-reaping logic.

## Important Concept

Zombies do **not** consume CPU or memory. They only occupy an entry in the process table (a PID slot). The real problem is the parent process behavior — the zombie is just a symptom. On systems with a low PID maximum (`/proc/sys/kernel/pid_max`), a large number of zombies can prevent new processes from being created.

## Root Cause

Common root causes include:

- **Parent process not calling `wait()`/`waitpid()`** — the most common cause; the application spawns child processes but does not collect their exit status
- **Buggy application** — a signal handler or event loop that ignores `SIGCHLD` or fails to reap children
- **Parent process crashed** — if the parent dies without reaping, children are reparented to PID 1, which usually handles this, but there can be a delay
- **Rapid process creation** — children are created faster than the parent reaps them, causing temporary accumulation

## Resolution

You **cannot** kill a zombie process — it is already dead. The `kill` command has no effect on a process in `Z` state. Instead, address the parent process.

### Option 1: Send SIGCHLD to the parent

```bash
kill -s SIGCHLD <parent-pid>
```

This asks the parent to check for and reap any terminated children. This works if the parent has a proper `SIGCHLD` handler but simply missed the signal.

### Option 2: Restart the parent process

If the parent is a long-running service with a bug in its child-reaping logic, restarting it will cause all its zombie children to be reparented to PID 1, which will reap them:

```bash
systemctl restart <service-name>
```

### Option 3: Fix the application

If the parent is a custom application, the source code needs to be fixed to properly call `wait()` or `waitpid()` when child processes exit. This is the correct long-term fix.

## Verification

After applying the fix, confirm the zombie count has dropped:

```bash
ps aux | awk '$8=="Z"' | wc -l
```

The count should be zero or close to zero. Monitor for a period to confirm zombies do not accumulate again:

```bash
watch -n 5 'ps aux | awk '\''$8=="Z"'\'' | wc -l'
```

Also verify the parent process is healthy:

```bash
ps -p <parent-pid> -o pid,stat,comm,args
```

The parent should be in a normal state (`S` or `R`), not stuck or unresponsive.

## Prevention

- **Fix the parent application** to properly reap children by calling `wait()` or `waitpid()` in a `SIGCHLD` handler or event loop
- **Use double-fork** — the parent forks, the child forks again and exits immediately, and the grandchild is reparented to PID 1, which always reaps it
- **Use `prctl(PR_SET_CHILD_SUBREAPER)`** — designates a process as a sub-reaper so it can collect orphaned descendants without relying on PID 1
- **Monitor zombie count** — set up a monitoring check that alerts when the zombie count exceeds a threshold, so the problem is caught before it grows
- **Review signal handling** — ensure the application does not block or ignore `SIGCHLD` unintentionally
