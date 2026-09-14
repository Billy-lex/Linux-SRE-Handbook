# System Boot Failure

## Problem

A Linux system fails to boot normally. The boot process may hang, drop to an emergency or rescue shell, display a kernel panic, or show a GRUB error. The system is unreachable and services do not start.

## Symptoms

- System hangs during boot with no further progress
- Drops to emergency shell or rescue mode
- Kernel panic message on screen
- GRUB error such as `error: file not found` or `grub rescue>`
- Specific services fail to start during boot, blocking the boot target
- System reboots in a loop

## Troubleshooting

Work through these steps in order. Boot failures require systematic elimination — do not jump to a fix without understanding where the boot process stops.

### Step 1 — Read the boot messages on screen

Watch the console output during boot. The last messages before the system stops usually point to the failing component. If the messages scroll too fast, reboot and look for the point where output freezes or errors appear.

On many distributions you can toggle verbose boot output by removing `rhgb quiet` (or `splash quiet`) from the kernel command line in GRUB.

### Step 2 — Check the boot log

If the system reaches at least a rescue shell or emergency mode:

```bash
journalctl -xb
```

The `-x` flag adds explanatory text for known error codes, and `-b` shows logs for the current (failed) boot. Look for lines marked `FAILED` or `error`.

If you need logs from the previous boot (before the failure):

```bash
journalctl -xb -1
```

### Step 3 — Check which systemd units failed

```bash
systemctl list-units --failed
```

This shows units that did not start successfully. A single failed unit — especially a mount unit or a critical service — can block the entire boot target.

For more detail on a specific failed unit:

```bash
systemctl status <unit-name>
journalctl -u <unit-name>
```

### Step 4 — Check /etc/fstab

An incorrect or missing entry in `/etc/fstab` is one of the most common boot failure causes. If a filesystem listed in `fstab` cannot be mounted, systemd will drop to emergency mode.

```bash
cat /etc/fstab
```

Look for:

- UUIDs or device paths that no longer exist (disk replaced, partition removed)
- Typos in mount points or filesystem types
- Filesystems that require a network (e.g., NFS) mounted without the `_netdev` option

Verify that every UUID in `fstab` matches an actual block device:

```bash
blkid
```

Compare the UUIDs from `blkid` against those in `/etc/fstab`.

### Step 5 — Boot into rescue mode or single-user mode via GRUB

If the system does not reach a usable shell, interrupt the GRUB menu and edit the boot entry:

1. Press `e` on the GRUB menu entry to edit it.
2. Find the line starting with `linux` (or `linux16`).
3. Append `single` or `init=/bin/bash` to the end of that line.
4. Press `Ctrl+X` or `F10` to boot.

This gives you a root shell with minimal services running, which is essential for fixing boot-blocking problems.

> **Safety:** When booting with `init=/bin/bash`, the root filesystem is mounted read-only. Remount it read-write before making changes:
>
> ```bash
> mount -o remount,rw /
> ```

### Step 6 — Check filesystem integrity

Filesystem corruption can prevent mounting and cause boot failure.

```bash
fsck -n /dev/sdXN
```

The `-n` flag performs a read-only check without making changes. Use this first to assess the damage.

> **Warning:** Never run `fsck` on a mounted filesystem. If you need to repair the root filesystem, boot from a live CD/USB or use rescue mode where the filesystem is not mounted.

To repair after confirming corruption:

```bash
fsck -y /dev/sdXN
```

### Step 7 — Try booting an older kernel

A recent kernel update may have introduced a driver or module incompatibility. From the GRUB menu, select `Advanced options` and choose a previous kernel version.

If the older kernel boots successfully, the problem is likely the newest kernel or its initramfs. You can set the older kernel as the default temporarily:

```bash
# RHEL/CentOS
grubby --set-default /boot/vmlinuz-<version>

# Check current default
grubby --default-kernel
```

### Step 8 — Check the bootloader and initramfs

If GRUB itself is damaged or misconfigured:

```bash
# RHEL/CentOS/Fedora
grub2-mkconfig -o /boot/grub2/grub.cfg

# Debian/Ubuntu
update-grub
```

Verify that the `/boot` partition contains the expected kernel and initramfs images:

```bash
ls -lh /boot/vmlinuz-* /boot/initramfs-*
```

If the initramfs is missing or corrupted for the current kernel, rebuild it:

```bash
# RHEL/CentOS/Fedora
dracut --force /boot/initramfs-$(uname -r).img $(uname -r)

# Debian/Ubuntu
update-initramfs -u
```

> **Warning:** Bootloader changes can make the system unbootable. If possible, test in a VM first. Always keep a known-good kernel entry in GRUB as a fallback.

## Root Cause

1. **Corrupted or incorrect /etc/fstab** — a UUID mismatch, typo, or removed disk causes systemd to fail when mounting filesystems at boot.
2. **Filesystem corruption** — power loss, hardware fault, or unclean shutdown corrupts the filesystem, preventing it from being mounted.
3. **Kernel panic** — a faulty driver, incompatible module, or bad kernel update crashes the kernel early in the boot process.
4. **Failed systemd unit blocking boot** — a critical service or mount unit fails, preventing the system from reaching the default target.
5. **Full /boot partition** — no space remains for new kernel or initramfs images, causing kernel updates or initramfs rebuilds to fail silently.
6. **GRUB misconfiguration** — the bootloader configuration references a missing kernel, wrong root device, or corrupted config file.
7. **Hardware failure** — a failing disk, bad memory, or controller issue prevents the system from reading boot-critical data.

## Resolution

### Fix /etc/fstab

Boot into rescue mode (Step 5). Edit `/etc/fstab` and correct or comment out the problematic entry. If a disk was permanently removed, remove or comment out its line:

```bash
vi /etc/fstab
```

After editing, test the corrected fstab without rebooting:

```bash
mount -a
```

### Repair filesystem corruption

Boot from a live CD/USB or into rescue mode. Run `fsck` on the affected unmounted partition:

```bash
fsck -y /dev/sdXN
```

Reboot after repair and verify the system starts normally.

### Boot an older kernel and fix the broken one

Boot the older kernel from GRUB. Once the system is up, rebuild the initramfs for the problematic kernel:

```bash
dracut --force /boot/initramfs-<broken-version>.img <broken-version>
```

Then attempt to boot the fixed kernel.

### Rebuild GRUB configuration

If GRUB is misconfigured, regenerate its config:

```bash
grub2-mkconfig -o /boot/grub2/grub.cfg
```

If the bootloader itself is damaged (e.g., MBR/EFI entry lost), reinstall it:

```bash
# BIOS/MBR
grub2-install /dev/sdX

# EFI
grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=fedora
```

### Free space on /boot

If `/boot` is full, remove old kernel packages that are no longer needed:

```bash
# RHEL/CentOS
dnf remove --oldinstallonly --setopt installonly_limit=2 kernel

# Debian/Ubuntu
apt autoremove --purge
```

## Verification

After applying the fix, reboot and confirm the system starts normally:

```bash
reboot
```

Once the system is up:

```bash
systemctl is-system-running
```

Expected output: `running`. If it shows `degraded`, check remaining failed units:

```bash
systemctl list-units --failed
```

Confirm the boot log is clean:

```bash
journalctl -xb -p err
```

This filters for errors in the current boot. A clean boot should show no critical errors related to the fix you applied.

## Prevention

- **Keep older kernels as fallback** — do not remove all previous kernel versions; keep at least one known-good kernel available in GRUB.
- **Test fstab changes before rebooting** — always run `mount -a` after editing `/etc/fstab` to catch errors while the system is still running.
- **Use `systemd-analyze` to check boot dependencies** — `systemd-analyze critical-chain` shows which units are on the critical boot path, helping you understand what can block boot.
- **Keep `/boot` from filling up** — monitor `/boot` usage and clean old kernels periodically. Set `installonly_limit` in `dnf.conf` to cap the number of installed kernels.
- **Test kernel updates in a VM first** — if possible, validate new kernels in a non-production environment before applying them to critical systems.
- **Maintain a rescue medium** — keep a live USB or ISO available so you can access the system even when the bootloader or root filesystem is damaged.
