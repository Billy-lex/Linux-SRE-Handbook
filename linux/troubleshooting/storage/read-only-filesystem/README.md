# Read-Only Filesystem

## Problem

A filesystem has been remounted as read-only by the kernel, preventing any write operations. This typically happens when the kernel detects filesystem errors and protects the data by switching to read-only mode.

## Symptoms

- "Read-only file system" error when attempting to write, create, or delete files
- Services fail to write logs or data (e.g., database cannot update files, application logs stop)
- Commands like `touch`, `mkdir`, or package installs fail with read-only errors
- System may still appear functional for read operations

## Troubleshooting

### Step 1: Check which filesystems are mounted read-only

```bash
findmnt -O ro
```

This lists only filesystems currently mounted read-only. If `findmnt` is not available, use:

```bash
awk '$4 ~ /(^|,)ro(,|$)/' /proc/mounts
```

Identify which mount point is causing the problem.

### Step 2: Check for filesystem errors in the kernel log

```bash
dmesg | tail -50
```

Look for messages such as `EXT4-fs error`, `XFS error`, or `I/O error`. These messages indicate why the kernel remounted the filesystem as read-only.

### Step 3: Check kernel messages about read-only remounting

```bash
journalctl -k | grep -i "read-only"
```

This confirms whether the kernel deliberately remounted the filesystem to protect data integrity.

### Step 4: Check disk health for hardware issues

```bash
smartctl -a /dev/sdX
```

If `smartctl` is available, check for signs of disk failure (reallocated sectors, pending sectors, SMART status). Replace `/dev/sdX` with the actual device name.

### Step 5: Verify actual mount options

```bash
cat /proc/mounts | grep /mountpoint
```

`/proc/mounts` reflects the kernel's current view of mount options, which is more reliable than the `mount` command output.

## Root Cause

Common causes include:

- **Filesystem corruption** — An unclean shutdown, power loss, or forced reboot left the filesystem in an inconsistent state. The kernel detects this on the next mount or during operation.
- **Kernel-detected errors** — The filesystem driver found errors during normal operation (bad metadata, journal errors, I/O errors) and remounted read-only to prevent further corruption.
- **Disk hardware failure** — Failing disks produce I/O errors that cause the kernel to remount the filesystem as read-only as a protective measure.

## Resolution

> **WARNING: Never run `fsck` on a mounted filesystem. This can cause severe data corruption.**

**For ext4 filesystems:**

1. Unmount the filesystem:

   ```bash
   umount /mountpoint
   ```

2. Run a filesystem check:

   ```bash
   fsck /dev/sdXN
   ```

   Replace `/dev/sdXN` with the actual device partition. `fsck` will detect and offer to repair corruption.

3. Remount the filesystem:

   ```bash
   mount /dev/sdXN /mountpoint
   ```

**For XFS filesystems:**

1. Unmount the filesystem:

   ```bash
   umount /mountpoint
   ```

2. Repair with `xfs_repair`:

   ```bash
   xfs_repair /dev/sdXN
   ```

3. Remount the filesystem:

   ```bash
   mount /dev/sdXN /mountpoint
   ```

**To remount read-write without unmounting** (only if the filesystem is healthy and you need a quick recovery):

```bash
mount -o remount,rw /mountpoint
```

This does not fix underlying corruption. Run `fsck` or `xfs_repair` at the next maintenance window.

**If the cause is hardware failure:**

- Replace the failing disk
- Restore data from backup

## Verification

After repair, confirm the filesystem is writable and healthy:

```bash
mount | grep /mountpoint
```

Verify the mount options no longer include `ro`.

```bash
touch /mountpoint/testfile && rm /mountpoint/testfile
```

Confirm that write operations succeed.

```bash
dmesg | tail -20
```

Check that no new filesystem errors appear after the repair.

## Prevention

- **Regular filesystem checks** — Schedule periodic `fsck` or `xfs_repair` runs during maintenance windows to catch corruption early.
- **Use a UPS** — Uninterruptible power supplies prevent unclean shutdowns from power loss, which is a leading cause of filesystem corruption.
- **Monitor disk health** — Use `smartctl` with periodic checks or automated monitoring (e.g., smartd) to detect failing disks before they cause errors.
- **Maintain backups** — Regular backups ensure data can be restored if a disk fails beyond repair.
