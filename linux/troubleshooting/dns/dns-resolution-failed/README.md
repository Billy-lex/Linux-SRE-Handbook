# DNS Resolution Failed

## Problem

The system cannot resolve hostnames to IP addresses, causing applications and commands that rely on domain names to fail while direct IP-based connectivity still works.

## Symptoms

- Commands return `Name or service not known` or `Could not resolve host`
- Applications fail to connect when using hostnames but work with IP addresses
- `ping google.com` fails but `ping 8.8.8.8` works
- `curl`, `wget`, or other tools report DNS-related errors
- Some hostnames resolve while others do not

## Troubleshooting

### Step 1: Check which DNS servers are configured

```bash
cat /etc/resolv.conf
```

Look at the `nameserver` lines. These are the DNS servers the system will query. If the file is empty, missing, or points to an unreachable server, resolution will fail.

Note: on systems using `systemd-resolved`, this file may be a symlink pointing to a stub resolver (e.g., `127.0.0.53`). In that case, check the actual upstream configuration:

```bash
resolvectl status
```

### Step 2: Test DNS resolution with dig

```bash
dig example.com
```

Check the `ANSWER SECTION` for returned records and the `SERVER` line to see which DNS server responded. A `status: SERVFAIL` or `status: REFUSED` indicates a server-side problem. A `status: NOERROR` with no answers may indicate a missing record.

### Step 3: Test against a known public DNS server

```bash
dig @8.8.8.8 example.com
```

If this succeeds but the default query fails, the problem is with the configured DNS server — not with DNS in general or with the network.

### Step 4: Trace the full DNS resolution path

```bash
dig example.com +trace
```

This follows the resolution from the root nameservers down to the authoritative server for the domain. It helps identify where in the chain the resolution breaks — for example, a specific authoritative server is unreachable or returns wrong data.

### Step 5: Check network connectivity to the DNS server

```bash
ping 8.8.8.8
```

If the system is configured to use a specific DNS server, ping that server's IP. If the ping fails, the DNS server is unreachable at the network level and the problem is connectivity, not DNS configuration.

### Step 6: Check the name service switch configuration

```bash
grep hosts /etc/nsswitch.conf
```

The `hosts:` line should include `dns`. A typical correct line looks like:

```
hosts:      files dns
```

If `dns` is missing, the system will not query DNS servers at all — it will only check `/etc/hosts`.

### Step 7: Check for stale entries in /etc/hosts

```bash
cat /etc/hosts
```

Entries in `/etc/hosts` take precedence over DNS (when `files` appears before `dns` in `nsswitch.conf`). A stale or incorrect entry will override the real DNS record and cause resolution to return the wrong IP or fail.

### Step 8: Check if a local DNS cache is running

```bash
systemctl status systemd-resolved
```

```bash
systemctl status dnsmasq
```

If the system relies on a local DNS cache (`systemd-resolved`, `dnsmasq`, `unbound`), check that the service is running and healthy. A crashed or misconfigured local resolver will block all DNS queries.

## Root Cause

Common root causes include:

- **Wrong DNS server in resolv.conf** — the configured nameserver is incorrect, outdated, or no longer exists
- **DNS server unreachable** — network issue prevents reaching the DNS server (routing, interface down, wrong gateway)
- **DNS server down** — the upstream DNS server is not responding to queries
- **Stale /etc/hosts entry** — a hardcoded entry overrides the correct DNS record
- **nsswitch.conf misconfigured** — `dns` is missing from the `hosts:` line, so DNS is never queried
- **Firewall blocking port 53** — a local or network firewall blocks DNS traffic (UDP/TCP port 53)

## Resolution

The fix depends on the root cause identified:

**Wrong or missing DNS server in resolv.conf:**

Edit `/etc/resolv.conf` to include a working nameserver:

```bash
# Temporary fix (will be overwritten by DHCP or network manager)
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
```

For a persistent fix, configure DNS through the network manager or DHCP settings rather than editing the file directly.

**DNS server unreachable:** Fix the network connectivity issue first — check the interface, routing table, and gateway:

```bash
ip addr show
ip route show
```

**Stale /etc/hosts entry:** Remove or correct the incorrect line in `/etc/hosts`.

**nsswitch.conf misconfigured:** Add `dns` to the `hosts:` line:

```
hosts:      files dns
```

**Firewall blocking port 53:** Allow DNS traffic through the firewall:

```bash
# Example for firewalld
firewall-cmd --add-service=dns --permanent
firewall-cmd --reload
```

**Local DNS cache service crashed:** Restart the service:

```bash
systemctl restart systemd-resolved
```

## Verification

After applying the fix, confirm DNS resolution works:

```bash
dig example.com
```

Confirm the `ANSWER SECTION` contains the expected records and the `status` is `NOERROR`.

Test with multiple hostnames to verify general resolution:

```bash
ping -c 2 google.com
ping -c 2 github.com
```

Test against the configured DNS server specifically:

```bash
dig @$(grep nameserver /etc/resolv.conf | head -1 | awk '{print $2}') example.com
```

## Prevention

- Configure at least two DNS servers in `resolv.conf` for redundancy
- Monitor DNS resolution with periodic checks (e.g., scheduled `dig` against a known domain)
- Consider running a local DNS cache (`systemd-resolved`, `dnsmasq`, `unbound`) to reduce dependency on upstream servers and improve response times
- Document DNS configuration as part of the system's network setup so changes are tracked
- Use infrastructure-as-code or configuration management to manage `/etc/resolv.conf` and `/etc/nsswitch.conf` consistently across systems
- Test DNS resolution after network changes or firewall updates
