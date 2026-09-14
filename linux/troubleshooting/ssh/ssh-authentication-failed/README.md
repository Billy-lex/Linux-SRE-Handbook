# SSH Authentication Failed

## Problem

An SSH connection attempt fails with a "Permission denied" error. The client cannot authenticate to the server, even though the network connection succeeds.

## Symptoms

- Connection fails with: `Permission denied (publickey,password)`
- Connection fails with: `Permission denied (publickey)`
- The login prompt keeps asking for a password but never accepts it
- SSH exits immediately without offering any authentication method

## Troubleshooting

### Step 1: Run SSH in verbose mode

```bash
ssh -vvv user@host
```

This shows which authentication methods the client attempts and which ones the server rejects. Look for lines like:

- `Authentications that can continue: publickey,password` — what the server allows
- `Next authentication method: publickey` — what the client tries
- `Offering public key: /home/user/.ssh/id_rsa` — which key is offered
- `Server refused our key` — the server rejected the key

The verbose output tells you whether the client is offering the right key and whether the server accepts the method at all.

### Step 2: Check server-side sshd_config

```bash
grep -E "^(PasswordAuthentication|PubkeyAuthentication|AuthorizedKeysFile|PermitRootLogin)" /etc/ssh/sshd_config
```

Confirm:
- `PubkeyAuthentication yes` — public key auth must be enabled
- `PasswordAuthentication yes` — if you expect password login, this must be enabled
- `AuthorizedKeysFile` — check whether it points to the expected location (default is `~/.ssh/authorized_keys`)

Also check for override files:

```bash
ls /etc/ssh/sshd_config.d/
```

On modern RHEL/CentOS and Ubuntu systems, drop-in files in this directory can override the main configuration.

### Step 3: Check the authorized_keys file on the server

```bash
cat ~/.ssh/authorized_keys
```

Confirm the client's public key is present. Compare with the key the client is offering:

```bash
# On the client side
cat ~/.ssh/id_rsa.pub
```

If the key is missing, add it. If the file does not exist, create it.

### Step 4: Check permissions

SSH is strict about file permissions. Incorrect permissions cause silent authentication failures.

```bash
# Home directory must not be group/world writable
ls -ld ~
# Should be 755 or stricter (e.g., 700)

# .ssh directory must be 700
ls -ld ~/.ssh
# Expected: drwx------ (700)

# authorized_keys must be 600
ls -l ~/.ssh/authorized_keys
# Expected: -rw------- (600)
```

Fix permissions if needed:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chmod go-w ~
```

Also verify ownership. The files must be owned by the target user:

```bash
ls -la ~/.ssh/
```

If running as root on the server, ensure you are checking the correct user's home directory, not root's.

### Step 5: Check server logs

On RHEL/CentOS:

```bash
journalctl -u sshd --since "5 minutes ago"
```

Or check the traditional log:

```bash
tail -50 /var/log/secure
```

On Ubuntu/Debian:

```bash
journalctl -u ssh --since "5 minutes ago"
```

Look for messages such as:
- `Authentication refused: bad ownership or modes for file /home/user/.ssh/authorized_keys` — permission problem
- `Connection closed by authenticating user` — key was rejected
- `Failed password for user` — password authentication attempted and failed

The server logs often reveal the exact reason for refusal, which the client does not see.

### Step 6: Check if the user account is locked

```bash
passwd -S <user>
```

A locked account shows `LK` or `L` in the status field. A locked account cannot log in via SSH, even with a valid key.

To unlock:

```bash
passwd -u <user>
```

Also check if the account has an expired password:

```bash
chage -l <user>
```

If the password has expired and `PasswordAuthentication` is the method, SSH may fail.

### Step 7: Check if root login is disabled

If you are trying to log in as root:

```bash
grep "^PermitRootLogin" /etc/ssh/sshd_config
```

Common values:
- `no` — root login is completely blocked
- `prohibit-password` — only key-based login is allowed (default on many distros)
- `yes` — all methods allowed

## Root Cause

Common root causes include:

- **Wrong key** — the client is offering a different key than what is in `authorized_keys`
- **Key not in authorized_keys** — the public key was never added to the server
- **Wrong permissions** — `~/.ssh` is not `700`, `authorized_keys` is not `600`, or the home directory is group/world writable, causing sshd to reject the key
- **Account locked** — the user account is locked via `passwd -l` or has an expired password
- **PasswordAuthentication disabled** — the server only allows key-based auth, but the client has no key configured
- **Wrong username** — attempting to log in as a user that does not exist on the server
- **Root login disabled** — attempting `ssh root@host` when `PermitRootLogin` is set to `no`

## Resolution

Apply the fix that matches the root cause identified:

**Key not present or wrong key:**

```bash
# On the client, copy the public key to the server
ssh-copy-id user@host
```

Or manually add the public key to the server's `~/.ssh/authorized_keys`.

**Wrong permissions:**

```bash
chmod go-w ~
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chown -R $(whoami):$(whoami) ~/.ssh
```

**Account locked:**

```bash
passwd -u <user>
```

**PasswordAuthentication disabled but needed:**

Edit `/etc/ssh/sshd_config`:

```
PasswordAuthentication yes
```

Then restart sshd:

```bash
systemctl restart sshd
```

**Wrong username:** Use the correct username in the SSH command or specify it explicitly:

```bash
ssh correct_user@host
```

**sshd_config changed:** Always restart sshd after configuration changes:

```bash
systemctl restart sshd
```

## Verification

After applying the fix, test the connection:

```bash
ssh user@host
```

If it succeeds, run verbose mode to confirm the expected authentication method was used:

```bash
ssh -v user@host
```

Look for a line similar to:

```
debug1: Authentication succeeded (publickey)
```

or:

```
debug1: Authentication succeeded (password)
```

If the fix involved permission changes, verify they are correct:

```bash
stat -c "%a %U %n" ~ ~/.ssh ~/.ssh/authorized_keys
```

Expected output:
- Home directory: `755` or `700`
- `~/.ssh`: `700`
- `~/.ssh/authorized_keys`: `600`

## Prevention

- **Use ssh-agent** — load keys once per session instead of typing passphrases repeatedly:

```bash
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa
```

- **Use an SSH config file** — define common hosts to avoid typing the full command and to ensure the correct key is always used:

```
# ~/.ssh/config
Host webserver
    HostName 192.168.1.10
    User deploy
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

- **Manage keys centrally** — use tools like `ssh-copy-id` to distribute keys consistently, or manage authorized keys through configuration management (Ansible, Puppet, etc.)

- **Test new keys immediately** — after adding a new key, verify it works before closing the current session, so you do not lock yourself out

- **Avoid password authentication** — key-based authentication is more secure and less prone to the issues described in this case
