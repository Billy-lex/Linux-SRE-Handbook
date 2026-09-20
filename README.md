# Linux SRE Handbook

A practical, case-based handbook for Linux troubleshooting.

This repository is designed for **daily reference, interview preparation, continuous learning, and professional portfolio use**.

The primary focus is not memorizing Linux commands, but developing a systematic approach to diagnosing and resolving real-world system problems.

---

## Core Workflow

Each troubleshooting case follows this operational mindset:

```text
Problem
   ↓
Troubleshooting
   ↓
Root Cause
   ↓
Resolution
   ↓
Automation
   ↓
Prevention
```

Not every case needs automation.

When automation provides meaningful value, the case may include a Bash or Python script.

The goal is to use the **simplest appropriate tool** for the job.

---

## Repository Structure

```text
linux-sre-handbook/
│
├── README.md
│
└── linux/
    └── troubleshooting/
        │
        ├── cpu/
        ├── memory/
        ├── storage/
        ├── process/
        ├── service/
        ├── networking/
        ├── dns/
        ├── ssh/
        ├── permissions/
        ├── boot/
        ├── logs/
        └── application/
```

Each directory contains troubleshooting cases organized by problem area.

Example:

```text
linux/
└── troubleshooting/
    └── storage/
        └── disk-full/
            ├── README.md
            └── check_disk.sh
```

A case may contain only documentation, or documentation together with automation and supporting files.

## Cases

| # | Category | Case | Description |
|---|----------|------|-------------|
| 1 | cpu | [high-cpu](linux/troubleshooting/cpu/high-cpu/) | CPU usage spike, locate the offending process |
| 2 | memory | [high-memory](linux/troubleshooting/memory/high-memory/) | Memory pressure, OOM killer, swap thrashing |
| 3 | storage | [disk-full](linux/troubleshooting/storage/disk-full/) | Filesystem out of space, includes `check_disk.sh` |
| 4 | storage | [inode-full](linux/troubleshooting/storage/inode-full/) | Inode exhaustion — space available but cannot create files |
| 5 | storage | [read-only-filesystem](linux/troubleshooting/storage/read-only-filesystem/) | Filesystem remounted read-only due to errors |
| 6 | process | [zombie-process](linux/troubleshooting/process/zombie-process/) | Zombie/defunct processes accumulating |
| 7 | service | [service-failed](linux/troubleshooting/service/service-failed/) | systemd service fails to start |
| 8 | networking | [port-not-listening](linux/troubleshooting/networking/port-not-listening/) | Port not listening, connection refused |
| 9 | dns | [dns-resolution-failed](linux/troubleshooting/dns/dns-resolution-failed/) | DNS resolution fails, hostname cannot be resolved |
| 10 | ssh | [ssh-connection-failed](linux/troubleshooting/ssh/ssh-connection-failed/) | Cannot establish SSH connection |
| 11 | ssh | [ssh-authentication-failed](linux/troubleshooting/ssh/ssh-authentication-failed/) | SSH key or password authentication rejected |
| 12 | permissions | [permission-denied](linux/troubleshooting/permissions/permission-denied/) | Permission denied — Unix, SELinux, ACL, immutable |
| 13 | boot | [boot-failure](linux/troubleshooting/boot/boot-failure/) | System fails to boot, rescue mode recovery |
| 14 | logs | [log-rotation-failed](linux/troubleshooting/logs/log-rotation-failed/) | logrotate not working, logs grow unchecked |
| 15 | application | [http-502-bad-gateway](linux/troubleshooting/application/http-502-bad-gateway/) | Reverse proxy returns 502, backend unreachable |
| 16 | storage | [disk-io-bottleneck](linux/troubleshooting/storage/disk-io-bottleneck/) | Disk I/O saturation — from symptom to identifying the offending process |
| 17 | application | [application-crash-loop](linux/troubleshooting/application/application-crash-loop/) | Service keeps crashing and restarting, includes `check_crash_loop.sh` |
| 18 | application | [http-503-service-unavailable](linux/troubleshooting/application/http-503-service-unavailable/) | Server returns 503 — overloaded, at capacity, or rejecting traffic, includes `check_503.sh` |
| 19 | application | [http-504-gateway-timeout](linux/troubleshooting/application/http-504-gateway-timeout/) | Backend too slow, proxy times out waiting, includes `check_504.sh` |

---

## Troubleshooting Cases

Each case is treated as an independent troubleshooting unit.

A typical case covers:

### 1. Problem

What happened?

What would the user or application experience?

### 2. Troubleshooting

What should be checked first?

Which commands or tools should be used?

What evidence should be collected?

### 3. Root Cause

What caused the problem?

Distinguish between the visible symptom, immediate cause, and underlying root cause when appropriate.

### 4. Resolution

What action fixes the problem?

How should the fix be verified?

### 5. Automation

Can any part of the investigation or detection be automated?

Possible tools include:

* Linux commands
* Bash
* Python

Automation is optional and should only be added when it provides practical value.

### 6. Prevention

How could the problem be detected earlier or prevented from happening again?

Examples include:

* Monitoring
* Alerting
* Log rotation
* Configuration changes
* Capacity planning
* Health checks
* Operational procedures

---

## Current Focus

The first phase focuses on Linux itself.

Major troubleshooting areas include:

* CPU and system load
* Memory and swap
* Processes
* Disk and filesystems
* Systemd and services
* Networking
* DNS
* SSH
* Permissions
* Boot and recovery
* Logs
* Application and HTTP problems

The goal is to build strong Linux troubleshooting fundamentals before expanding into broader infrastructure technologies.

---

## Practical Approach

Whenever practical, troubleshooting cases are reproduced in a controlled lab environment.

The preferred learning cycle is:

```text
Create / reproduce a problem
          ↓
Observe the symptoms
          ↓
Investigate
          ↓
Collect evidence
          ↓
Identify the root cause
          ↓
Fix the problem
          ↓
Verify recovery
          ↓
Document the solution
          ↓
Automate repetitive checks when useful
          ↓
Consider prevention
```

The lab environment may include local virtual machines or other disposable environments.

Destructive testing should never be performed on production systems.

---

## Quick Reference

This repository is intended to be useful during actual operations, not only during study.

Documentation should therefore be:

* Easy to search
* Practical
* Command-oriented
* Organized by problem
* Focused on symptoms and diagnosis
* Clear enough to use under time pressure

The emphasis is on:

> **What should I check when something goes wrong?**

rather than:

> **What does this Linux command do?**

---

## Interview Preparation

The same troubleshooting cases can be used to prepare for technical interviews.

Each case should help answer questions such as:

* How would you troubleshoot high CPU usage?
* How would you investigate a full filesystem?
* How would you troubleshoot a failed systemd service?
* How would you investigate an SSH connection failure?
* How would you troubleshoot a DNS problem?
* How would you determine whether a problem is network-related?
* How would you identify the root cause of an incident?

The goal is to explain the **reasoning and investigation process**, not simply list commands.

---

## Automation Philosophy

Automation should follow a simple rule:

> **Automate repeated operational work when automation provides real value.**

Use Linux commands when commands are sufficient.

Use Bash when a simple shell workflow is appropriate.

Use Python when more structured logic, data processing, error handling, or reusable tooling is useful.

Do not add automation merely to make a case look more complex.

---

## Long-Term Roadmap

The initial focus is Linux troubleshooting.

As the handbook grows, the scope may expand gradually:

```text
Linux
  ↓
Infrastructure
  ↓
Cloud
  ↓
Containers / Kubernetes
  ↓
Observability
  ↓
SRE / Incident Response
```

Future areas may include:

* Infrastructure troubleshooting
* AWS and Azure troubleshooting
* Docker and Kubernetes troubleshooting
* Monitoring and observability
* Incident response
* Root cause analysis
* Reliability and capacity planning
* SRE practices

These areas will be added only after the Linux foundation is sufficiently developed.

---

## Project Philosophy

This is a long-term personal reference and learning project.

It should remain:

* Practical
* Searchable
* Reproducible
* Honest
* Simple
* Continuously improving

Lab experience must not be presented as production experience.

The purpose is to demonstrate and develop the ability to:

> **Troubleshoot Linux systems systematically, identify root causes, resolve problems, automate useful operational tasks, and think about prevention and reliability.**
