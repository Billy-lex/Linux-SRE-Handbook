# Permission Denied

## Problem

"Permission denied" is one of the most common errors in Linux. It occurs when a user or process tries to access a file, directory, or resource without the required permissions. The cause is not always obvious — it can stem from standard Unix permissions, ownership, group membership, SELinux policies, ACLs, immutable attributes, or mount options.

## Symptoms

- "Permission denied" when reading, writing, or executing a file
- "Permission denied" when listing or entering a directory
- Commands fail with permission errors even when run as a privileged user
- Services fail to start because they cannot read configuration files or write to log/pid directories
- Scripts cannot be executed despite appearing to have correct permissions

## Troubleshooting

### 1. Check file and directory permissions and ownership

```bash
ls -la /path/to/file
```

This shows the permission bits (e.g., `-rw-r--r--`), owner, and group. The first character indicates the file type (`-` for regular file, `d` for directory). The next nine characters represent three sets of permissions: owner, group, and others. Each set can have `r` (read), `w` (write), and `x` (execute).

Common permission patterns:

- `755` (`rwxr-xr-x`) — directories and executables accessible by everyone, writable only by owner
- `644` (`rw-r--r--`) — regular files readable by everyone, writable only by owner
- `600` (`rw-------`) — private files readable and writable only by owner
- `700` (`rwx------`) — private directories accessible only by owner

### 2. Check the full path permission chain

```bash
namei -l /path/to/file
```

A file may have correct permissions, but if any parent directory in the path lacks execute (`x`) permission for your user, access is denied. `namei -l` shows the owner, group, and permission bits for every component from `/` down to the target. Every directory in the chain must grant at least execute permission to the accessing user.

### 3. Check current user identity and group membership

```bash
id
```

This displays the current UID, GID, and all supplementary groups. A file might be owned by a group your user is not a member of. If you were recently added to a group, you need to log out and back in (or run `newgrp <groupname>`) for the change to take effect in your current session.

### 4. Check Access Control Lists (ACLs)

```bash
getfacl /path/to/file
```

Standard `ls -la` only shows owner/group/others permissions. ACLs can grant or deny access to specific users or groups beyond that model. If standard permissions look correct but access is still denied, ACLs may be overriding them. Look for entries that explicitly deny access or that restrict the effective permissions mask.

### 5. Check SELinux status and security contexts

```bash
getenforce
```

If this returns `Enforcing`, SELinux is actively blocking operations that violate its policy — even when standard Unix permissions would allow them.

```bash
ls -Z /path/to/file
```

This shows the SELinux security context (e.g., `system_u:object_r:httpd_sys_content_t:s0`). A file created in one context may not be accessible to a process running in another context, even if the Unix permissions are correct.

Check the audit log for SELinux denials:

```bash
ausearch -m avc -ts recent
```

If denials are found, `audit2allow` can suggest policy adjustments:

```bash
ausearch -m avc -ts recent | audit2allow
```

### 6. Check the immutable attribute

```bash
lsattr /path/to/file
```

A file with the immutable attribute (`i` flag) cannot be modified, deleted, renamed, or linked — even by root. This is set with `chattr +i` and is sometimes used to protect critical configuration files. If `lsattr` shows the `i` flag, this is likely the cause.

### 7. Check filesystem mount options

```bash
mount | grep /path/to/mountpoint
```

Filesystems can be mounted with restrictive options:

- `ro` — read-only; no writes are allowed regardless of file permissions
- `noexec` — prevents execution of any binaries on that filesystem
- `nosuid` — ignores the SUID/SGID bits, so privilege escalation via setuid binaries is blocked

If the target file lives on a filesystem mounted with one of these flags, permission errors will occur even when the file's own permissions appear correct.

## Root Cause

The "Permission denied" error is caused by one or more of the following:

- **Wrong ownership** — the file is owned by a different user or group than expected
- **Wrong permissions** — the permission bits do not grant the required access (e.g., `600` instead of `644`, or missing execute bit on a script)
- **Missing group membership** — the user is not in the group that owns the file, or the group change has not been applied to the current session
- **SELinux policy** — the security context of the file or process prevents the operation, even though Unix permissions would allow it
- **Immutable attribute** — the file has the `i` flag set via `chattr`, preventing any modification
- **ACL restrictions** — an ACL entry overrides or restricts access beyond the standard owner/group/others model
- **Restrictive mount options** — the filesystem is mounted as `ro`, `noexec`, or `nosuid`
- **Missing execute permission on a parent directory** — any directory in the path must have the execute bit set for the accessing user

## Resolution

Apply the fix that matches the root cause identified during troubleshooting.

**Fix ownership:**

```bash
chown user:group /path/to/file
```

Recursively for directories:

```bash
chown -R user:group /path/to/directory
```

**Fix permissions:**

```bash
chmod 644 /path/to/file
chmod 755 /path/to/directory
chmod +x /path/to/script
```

**Add user to a group:**

```bash
usermod -aG groupname username
```

The user must log out and back in for the group change to take effect, or run `newgrp groupname` in the current shell.

**Fix SELinux context:**

Temporarily set SELinux to permissive mode for testing (not for production use):

```bash
setenforce 0
```

Change the security context of a file to match what the service expects:

```bash
chcon -t httpd_sys_content_t /path/to/file
```

To make the context change persistent across relabels, define it in the SELinux file context configuration and run `restorecon`.

**Remove the immutable attribute:**

```bash
chattr -i /path/to/file
```

**Adjust ACLs:**

```bash
setfacl -m u:username:rwx /path/to/file
setfacl -m g:groupname:rx /path/to/directory
```

**Remount with correct options:**

```bash
mount -o remount,rw /path/to/mountpoint
```

## Verification

After applying the fix, verify that the original operation now succeeds:

```bash
# Retry the operation that was failing
cat /path/to/file
ls /path/to/directory
./path/to/script
systemctl restart <service>
```

Confirm the permission state is as expected:

```bash
ls -la /path/to/file
namei -l /path/to/file
getfacl /path/to/file
lsattr /path/to/file
```

For SELinux-related fixes, re-enable enforcing mode and verify the service still works:

```bash
setenforce 1
systemctl restart <service>
```

## Prevention

- **Principle of least privilege** — grant only the minimum permissions required. Do not use `chmod 777` as a shortcut; it creates security risks and masks the real permission problem.
- **Use groups properly** — assign users to appropriate groups and set group ownership on shared resources, rather than opening permissions to "others."
- **Document permission requirements** — when deploying services or applications, document the expected file ownership and permission bits so they can be reproduced consistently.
- **Be cautious with `chattr +i`** — if you set the immutable flag on a file, record it in your configuration management or runbook so future troubleshooting is not blocked by a forgotten attribute.
- **Use configuration management** — tools like Ansible, Puppet, or Chef can enforce correct ownership and permissions across systems, preventing drift.
- **Test SELinux changes in permissive mode first** — before writing permanent policy modules, use `setenforce 0` in a non-production environment to confirm SELinux is the cause, then apply a targeted fix with `chcon` or a custom policy.
