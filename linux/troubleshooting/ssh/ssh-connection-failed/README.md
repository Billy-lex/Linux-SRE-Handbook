# SSH Connection Failed

## Problem

Attempting to connect to a remote server via SSH fails. The connection cannot be established, and the error message varies depending on the underlying cause.

## Symptoms

- `ssh: connect to host <host> port 22: Connection refused`
- `ssh: connect to host <host> port 22: Connection timed out`
- `ssh: connect to host <host> port 22: Network is unreachable`
- The SSH client hangs indefinitely without returning an error
- The connection drops immediately after being established

## Troubleshooting

### Step 1: Check if the host is reachable at all

```bash
ping <host>
```

If ping fails, the problem is network-level — the host may be down, disconnected, or blocked by an upstream firewall. If ping succeeds, the host is reachable at the IP layer and the problem is likely at the service or firewall level.

### Step 2: Check if sshd is listening on the server

```bash
ss -tlnp | grep 22
```

This shows whether the SSH daemon is bound to port 22 (or another port). If there is no output, sshd is either not running or listening on a non-standard port.

### Step 3: Check the SSH daemon status

```bash
systemctl status sshd
```

On Debian/Ubuntu systems the service may be named `ssh` instead:

```bash
systemctl status ssh
```

Look for `Active: active (running)`. If the service is `inactive` or `failed`, sshd needs to be started or restarted. Check the logs for why it stopped:

```bash
journalctl -u sshd --no-pager -n 50
```

### Step 4: Use verbose SSH output to pinpoint the failure

```bash
ssh -vvv user@host
```

The verbose output shows exactly where the connection fails — DNS resolution, TCP handshake, key exchange, or authentication. This is the single most useful command for narrowing down the cause.

### Step 5: Check firewall rules

On the server, check whether port 22 is blocked:

```bash
iptables -L -n | grep 22
```

If the system uses `firewalld`:

```bash
firewall-cmd --list-all
```

Look for whether port 22/tcp is listed in the allowed services or ports. A missing entry or an explicit DROP/REJECT rule will block SSH connections.

### Step 6: Check TCP wrappers

```bash
cat /etc/hosts.allow
cat /etc/hosts.deny
```

If `/etc/hosts.deny` contains `sshd: ALL` and `/etc/hosts.allow` does not have an entry permitting your IP, SSH connections will be rejected before authentication even begins.

### Step 7: Check sshd_config for port changes and access restrictions

```bash
grep -E "^(Port|AllowUsers|AllowGroups|DenyUsers|ListenAddress)" /etc/ssh/sshd_config
```

A non-default `Port` means the client must connect to that port explicitly. `AllowUsers` or `AllowGroups` directives restrict which accounts can log in — a valid user may still be denied if they are not listed.

### Step 8: Check the server's network interface

```bash
ip addr show
```

Verify that the expected network interface has an IP address assigned and is in the `UP` state. An interface that is `DOWN` or has no IP address will not accept connections.

## Root Cause

Common root causes include:

- **sshd not running** — the SSH daemon is stopped, crashed, or not enabled at boot
- **Firewall blocking port 22** — iptables, firewalld, or a cloud security group is dropping traffic to port 22
- **Network connectivity issue** — the server is unreachable due to routing problems, a disconnected cable, or a misconfigured network interface
- **Wrong port** — sshd is configured to listen on a non-standard port and the client is connecting to port 22
- **TCP wrappers blocking access** — `/etc/hosts.deny` is rejecting SSH connections from the client's IP
- **Network interface down** — the server's NIC is administratively down or has no IP address assigned

## Resolution

Apply the fix that matches the identified root cause:

**sshd not running:**

```bash
systemctl start sshd
systemctl enable sshd
```

**Firewall blocking port 22:**

```bash
# firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

# iptables
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
```

**Wrong port:** Connect with the correct port:

```bash
ssh -p <port> user@host
```

Or change the port back to 22 in `/etc/ssh/sshd_config` and restart sshd:

```bash
systemctl restart sshd
```

**TCP wrappers blocking access:** Add an allow rule to `/etc/hosts.allow`:

```text
sshd: <client-ip>
```

**Network interface down:**

```bash
ip link set <interface> up
```

Then obtain an IP address via DHCP if needed:

```bash
dhclient <interface>
```

## Verification

After applying the fix, confirm SSH connectivity from the client:

```bash
ssh user@host
```

If the port was changed:

```bash
ssh -p <port> user@host
```

On the server, verify sshd is running and listening:

```bash
systemctl status sshd
ss -tlnp | grep sshd
```

Confirm the firewall allows SSH traffic:

```bash
firewall-cmd --list-all
```

## Prevention

- Set up monitoring to check SSH availability (e.g., a periodic TCP check on port 22 from an external host)
- Keep an alternative access method available — console access, IPMI/iDRAC/iLO, or a cloud provider's serial console — so you are not locked out if SSH fails
- Document firewall rules and review them after changes; a new rule can unintentionally block SSH
- Enable sshd at boot (`systemctl enable sshd`) so it starts automatically after a reboot
- Use configuration management (Ansible, Puppet, etc.) to manage sshd_config and firewall rules, reducing the risk of manual misconfiguration
