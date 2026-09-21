# 🚀 MikroTik V9 Priority Hybrid QoS — Starlink Optimization for 200+ Users

[![MikroTik](https://img.shields.io/badge/MikroTik-RouterOS%206.48.6-blue)](https://mikrotik.com)
[![Starlink](https://img.shields.io/badge/WAN-Starlink%20Priority-purple)](https://starlink.com)
[![Users](https://img.shields.io/badge/Users-200%2B-green)]()
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

**A production-tested QoS system for MikroTik RouterOS 6.x managing 200+ hotspot users over Starlink, with real-time adaptive bandwidth control, per-user fairness, and gaming/streaming priority.**

> Built and battle-tested by **Eng. Hudhaifa Aref** (المهندس حذيفه عارف) on a live network serving 200+ concurrent users.

---

## 📋 Table of Contents

- [The Problem](#-the-problem)
- [The Solution](#-the-solution)
- [Architecture](#-architecture)
- [Key Features](#-key-features)
- [Performance Results](#-performance-results)
- [Installation](#-installation)
- [DynBW Adaptive Controller](#-dynbw-v9-adaptive-controller)
- [Queue Tree Structure](#-queue-tree-structure)
- [Mangle Rules](#-mangle-rules)
- [Tuning Guide](#-tuning-guide)
- [Troubleshooting](#-troubleshooting)
- [FAQ](#-faq)

---

## 🔴 The Problem

Managing 200+ hotspot users on Starlink with MikroTik presents unique challenges:

| Challenge | Impact |
|-----------|--------|
| **Starlink bandwidth fluctuates** (50-300 Mbps) | Static QoS either wastes bandwidth or causes bufferbloat |
| **No CAKE/fq_codel on RouterOS 6** | Limited queuing discipline options |
| **Gaming + Streaming + Browsing** all competing | PUBG ping spikes to 300ms+ during peak hours |
| **One user can hog all bandwidth** | Downloads saturate the link, everyone suffers |
| **FastTrack bypasses Queue Tree** | QoS becomes invisible to most traffic |
| **Upload is limited (~30 Mbps)** | Live streaming stutters, ACKs delayed |

### What Didn't Work
- ❌ Simple Queues — don't scale to 200+ users
- ❌ Static Queue Tree limits — waste bandwidth when Starlink is fast, cause drops when it's slow
- ❌ FastTrack + QoS — FastTrack bypasses everything
- ❌ Generic ACK priority — pollutes gaming queue with millions of ACK packets
- ❌ Single PCQ for all traffic — no service differentiation

---

## 🟢 The Solution

**V9 Priority Hybrid** combines five proven techniques into one cohesive system:

```
┌─────────────────────────────────────────────────────────┐
│                   V9 Priority Hybrid                     │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  HTB     │  │  PCQ     │  │  DynBW   │              │
│  │ Priority │  │ Fairness │  │ Adaptive │              │
│  │  Queue   │  │ Per-User │  │ Control  │              │
│  │  Tree    │  │          │  │          │              │
│  └──────────┘  └──────────┘  └──────────┘              │
│       +              +              +                    │
│  ┌──────────┐  ┌──────────┐                             │
│  │   DNS    │  │  ACK     │                             │
│  │ Priority │  │ Separate │                             │
│  │  Queue   │  │  Queue   │                             │
│  └──────────┘  └──────────┘                             │
└─────────────────────────────────────────────────────────┘
```

---

## 🏗 Architecture

### Priority Hierarchy

| Priority | Service | Download | Upload | Queue Type | Why |
|:--------:|---------|:--------:|:------:|:----------:|-----|
| **P1** | 🎯 DNS | 2M | 512K | default-small | Faster first-click for everything |
| **P1** | 🎮 Gaming (PUBG) | 20M | 5M | default-small | Smallest buffer = lowest jitter |
| **P2** | 📺 Live Streaming | 130M | 12M | default-small | Guaranteed 8M/2M even under load |
| **P3** | 💬 ACK/Small Packets | — | 4M | default-small | Keeps downloads responsive |
| **P3** | 📱 WhatsApp | 40M | 3M | default | Calls + media |
| **P3** | 📸 Instagram | 150M | 8M | default | Reels/Stories smooth |
| **P4** | 🌐 General Browsing | 150M | 15M | **pcq-dl-users** | Fair share per user |
| **P6** | 📦 Bulk Downloads | 100M | — | **pcq-dl-users** | Uses only leftover bandwidth |

### DynBW Adaptive Bandwidth Controller

```
         Starlink Capacity (fluctuating)
              │
    ┌─────────▼─────────┐
    │   DynBW V9        │  ← Runs every 60 seconds
    │                   │
    │ Reads: rate,      │
    │   queued-bytes,   │
    │   dropped packets │
    │                   │
    │ EMA smoothing     │
    │   (20/80 ratio)   │
    │                   │
    │ Decides: grow,    │
    │   stable, or      │
    │   shrink Parent   │
    └─────────┬─────────┘
              │
    ┌─────────▼─────────┐
    │  Global-Download   │  120M ←→ 249M
    │  Global-Upload     │   15M ←→  32M
    └───────────────────┘
         (Parent only — children untouched)
```

**Key Design Decision:** DynBW adjusts ONLY the parent queue limits. Child queues have fixed limits and compete under HTB priority rules. This means:
- Gaming always gets first access (P1)
- Streaming always gets second access (P2)
- General browsing gets fair-shared leftovers (P4, PCQ)
- Downloads get absolute lowest priority (P6)

---

## ✨ Key Features

### 1. PCQ Per-User Fairness
With 200+ users, without PCQ one heavy downloader eats all bandwidth. PCQ automatically divides available capacity equally among active users.

```routeros
/queue type add name="pcq-dl-users" kind=pcq \
    pcq-classifier=dst-address pcq-rate=0 \
    pcq-limit=50 pcq-total-limit=10000

/queue type add name="pcq-ul-users" kind=pcq \
    pcq-classifier=src-address pcq-rate=0 \
    pcq-limit=50 pcq-total-limit=10000
```

`pcq-rate=0` means "divide the parent's available bandwidth equally" — no static per-user limit needed.

### 2. DNS Priority Queue
DNS is the first request in any browsing/app interaction. Giving DNS P1 priority makes everything *feel* faster:

```routeros
/ip firewall mangle add chain=prerouting in-interface=IN \
    protocol=udp dst-port=53 action=mark-packet \
    new-packet-mark=dns-dl passthrough=no comment="V9-DNS-DL"
```

### 3. Separate ACK Queue (Not Gaming!)
A common mistake is putting ACK packets in the gaming queue. This pollutes the gaming queue with millions of ACK packets. V9 uses a separate P3 queue:

```routeros
# WRONG: ACK in Gaming queue
# /ip firewall mangle add ... new-packet-mark=gaming-ul  ← DON'T DO THIS

# RIGHT: Separate ACK queue with gaming exception
/ip firewall mangle add chain=postrouting out-interface=IN \
    protocol=tcp dst-port=3074,27015-27050,7000-8000 \
    packet-size=0-128 action=mark-packet \
    new-packet-mark=gaming-ul passthrough=no \
    comment="V9-TCPGAME-UL"

/ip firewall mangle add chain=postrouting out-interface=IN \
    protocol=tcp packet-size=0-128 action=mark-packet \
    new-packet-mark=small-ul passthrough=no \
    comment="V9-SMALL-UL"
```

### 4. Conservative Anti-Bufferbloat
DynBW uses triple-signal congestion detection:
- **EMA Utilization** — smoothed usage percentage
- **Queued Bytes** — actual queue depth
- **Drop Deltas** — packet drops between cycles

All three must agree before DynBW shrinks bandwidth:

```
CRITICAL: EMA ≥ 96% AND queued ≥ 512KB → shrink 7%
CONGESTED: EMA ≥ 90% AND queued ≥ 256KB → shrink 4%
STABLE: EMA ≥ 78% AND queued < 256KB AND drops = 0 → grow 3%
```

### 5. No FastTrack
FastTrack completely bypasses Mangle and Queue Tree. It must be disabled for any QoS to work:

```routeros
/ip firewall filter disable [find action=fasttrack-connection]
```

---

## 📊 Performance Results

### Real production data (200+ users, Starlink Priority):

| Metric | Before V9 | After V9 |
|--------|:---------:|:--------:|
| PUBG Ping (idle) | 60-80ms | **53-65ms** |
| PUBG Ping (peak) | 150-300ms | **65-90ms** |
| Streaming stutter | Frequent | **None** |
| Instagram loading | Slow during peak | **Smooth** |
| User complaints | Daily | **Rare** |
| Bandwidth waste | ~30% | **<5%** |
| CPU usage | 8-15% | **2-3%** |
| Packet loss (CF) | 0-5% | **0%** |

### DynBW Adaptation Log (real):
```
20:26 DynBW V9 DL=170M/29%/stable UL=27M/58%/stable
20:36 DynBW V9 DL=170M/93%/stable UL=27M/66%/stable
20:45 DynBW V9 DL 170M->175M U=100% E=92% S=growing
20:56 DynBW V9 DL 175M->180M U=75% E=82% S=growing
21:16 DynBW V9 DL 180M->185M U=94% E=83% S=growing
```

---

## 📥 Installation

### Prerequisites
- MikroTik RouterOS 6.x (tested on 6.48.6)
- Queue Tree already configured with parent queues
- Mangle rules for traffic classification (gaming, streaming, social media)
- FastTrack **disabled**

### Step 1: Backup
```routeros
/system backup save name="pre-V9-backup"
/export file="pre-V9-export"
```

### Step 2: Create PCQ Queue Types
```routeros
/queue type
add name="pcq-dl-users" kind=pcq pcq-classifier=dst-address \
    pcq-rate=0 pcq-limit=50 pcq-total-limit=10000
add name="pcq-ul-users" kind=pcq pcq-classifier=src-address \
    pcq-rate=0 pcq-limit=50 pcq-total-limit=10000
```

### Step 3: Add V9 Mangle Rules
```routeros
/ip firewall mangle

# DNS Priority (place at top)
add chain=prerouting in-interface=IN protocol=udp dst-port=53 \
    action=mark-packet new-packet-mark=dns-dl passthrough=no \
    comment="V9-DNS-DL" place-before=0
add chain=prerouting in-interface=IN protocol=tcp dst-port=53 \
    action=mark-packet new-packet-mark=dns-dl passthrough=no \
    comment="V9-DNS-DL" place-before=0
add chain=postrouting out-interface=IN protocol=udp src-port=53 \
    action=mark-packet new-packet-mark=dns-ul passthrough=no \
    comment="V9-DNS-UL" place-before=0
add chain=postrouting out-interface=IN protocol=tcp src-port=53 \
    action=mark-packet new-packet-mark=dns-ul passthrough=no \
    comment="V9-DNS-UL" place-before=0

# Gaming TCP exception (before Small-UL)
add chain=postrouting out-interface=IN protocol=tcp \
    dst-port=3074,27015-27050,7000-8000 packet-size=0-128 \
    action=mark-packet new-packet-mark=gaming-ul passthrough=no \
    comment="V9-TCPGAME-UL" place-before=0

# Small packets / ACK (separate from Gaming)
add chain=postrouting out-interface=IN protocol=tcp \
    packet-size=0-128 action=mark-packet \
    new-packet-mark=small-ul passthrough=no \
    comment="V9-SMALL-UL"
```

### Step 4: Configure Queue Tree
```routeros
/queue tree

# Download
set [find name="Global-Download"] max-limit=220M
add name="0-DNS-Download" parent=Global-Download packet-mark=dns-dl \
    priority=1 limit-at=256k max-limit=2M queue=default-small
set [find name="0-Gaming-Download"] limit-at=5M max-limit=20M \
    priority=1 queue=default-small
set [find name="4-Streaming-Download"] limit-at=8M max-limit=130M \
    priority=2 queue=default-small
set [find name="3-WhatsApp-Download"] limit-at=1M max-limit=40M priority=3
set [find name="3-Instagram-Download"] limit-at=2M max-limit=150M priority=3
set [find name="1-Download-Root"] limit-at=5M max-limit=150M \
    priority=4 queue=pcq-dl-users
set [find name="6-Bulk-Download"] limit-at=0 max-limit=100M \
    priority=6 queue=pcq-dl-users

# Upload
set [find name="Global-Upload"] max-limit=27M
add name="0-DNS-Upload" parent=Global-Upload packet-mark=dns-ul \
    priority=1 limit-at=64k max-limit=512k queue=default-small
set [find name="2-Gaming-Upload"] limit-at=512k max-limit=5M \
    priority=1 queue=default-small
set [find name="5-Streaming-Upload"] limit-at=2M max-limit=12M \
    priority=2 queue=default-small
add name="3-Small-UL" parent=Global-Upload packet-mark=small-ul \
    priority=3 limit-at=1M max-limit=4M queue=default-small
set [find name="3-WhatsApp-Upload"] limit-at=256k max-limit=3M priority=3
set [find name="3-Instagram-Upload"] limit-at=512k max-limit=8M priority=3
set [find name="3-Upload-Root"] limit-at=0 max-limit=15M \
    priority=4 queue=pcq-ul-users
```

### Step 5: Upload DynBW V9 Script
Upload `DynBW-V9.rsc` to the router via Winbox Files or SFTP, then:

```routeros
# Test run
/import file-name=DynBW-V9.rsc

# Verify
/queue tree print where name=Global-Download
# Should show max-limit near your dlStart value

# Set scheduler
/system scheduler add name="DynBW-V9-Scheduler" interval=1m \
    on-event=":do { /import file-name=DynBW-V9.rsc } on-error={}" \
    policy=read,write,policy,test comment="V9 Adaptive QoS Controller"
```

---

## 🔧 DynBW V9 Adaptive Controller

The full DynBW V9 script is in [`DynBW-V9.rsc`](DynBW-V9.rsc).

### Key Parameters

| Parameter | Default | Description |
|-----------|:-------:|-------------|
| `dlStart` | 220M | Initial download parent limit |
| `dlMin` | 120M | Floor — never goes below this |
| `dlMax` | 249M | Ceiling — never exceeds this |
| `ulStart` | 27M | Initial upload parent limit |
| `ulMin` | 15M | Upload floor |
| `ulMax` | 32M | Upload ceiling |
| `growStep` | 3% | How much to grow per step |
| `downStep` | 4% | How much to shrink on congestion |
| `criticalDownStep` | 7% | Emergency shrink on critical congestion |
| `growCycles` | 3 | Stable cycles needed before growing |
| `congestCycles` | 2 | Congested cycles before shrinking |
| `cooldownCycles` | 3 | Wait cycles after any change |
| `utilGrow` | 78% | EMA threshold to consider growing |
| `utilCongest` | 90% | EMA threshold for congestion |
| `utilCritical` | 96% | EMA threshold for critical |

### State Machine

```
                    ┌───────────┐
          ┌────────►│  STABLE   │◄────────┐
          │         └─────┬─────┘         │
          │               │               │
     cooldown        6 stable          no signal
          │          cycles               │
          │               │               │
          │         ┌─────▼─────┐         │
          ├─────────│  GROWING  │─────────┤
          │         └───────────┘         │
          │                               │
          │         ┌───────────┐         │
          ├─────────│ CONGESTED │─────────┘
          │         └───────────┘
          │
          │         ┌───────────┐
          └─────────│ CRITICAL  │
                    └───────────┘
```

---

## 🎯 Tuning Guide

### For Different WAN Speeds

| WAN Speed | dlStart | dlMin | dlMax | ulStart | ulMax |
|:---------:|:-------:|:-----:|:-----:|:-------:|:-----:|
| 50 Mbps | 40M | 25M | 50M | 8M | 10M |
| 100 Mbps | 80M | 50M | 100M | 15M | 20M |
| 200 Mbps | 160M | 100M | 200M | 25M | 30M |
| 300 Mbps | 220M | 120M | 300M | 27M | 40M |

### For Different User Counts

| Users | Root max-limit | Bulk max-limit | PCQ |
|:-----:|:--------------:|:--------------:|:---:|
| < 50 | 80M | 60M | Optional |
| 50-100 | 120M | 80M | Recommended |
| 100-200 | 150M | 100M | Required |
| 200+ | 180M | 120M | Required |

---

## ❓ FAQ

**Q: Does this work with RouterOS 7?**
A: The Queue Tree and Mangle logic works. But RouterOS 7 has `fq_codel` which is better than `default-small`. Consider using fq_codel as queue type instead.

**Q: Can I use this without Starlink?**
A: Yes! Adjust `dlMin/dlMax/ulMin/ulMax` to match your WAN speed. The adaptive logic works with any ISP.

**Q: Why not use Simple Queues?**
A: Simple Queues don't scale. With 200+ users, you'd need 200+ queue entries. Queue Tree + PCQ handles this automatically.

**Q: Why is FastTrack disabled?**
A: FastTrack bypasses both Mangle (packet marking) and Queue Tree completely. With FastTrack on, your QoS rules are invisible to most traffic.

**Q: My PUBG ping is still high — is it QoS?**
A: If `ping 1.1.1.1` shows 60-90ms but PUBG shows 200ms+, the issue is the game server routing, not your QoS. MikroTik QoS controls local queuing only.

---

## 🛡 Safety Rules

1. **Never re-enable FastTrack** with Queue Tree active
2. **Never put ACK packets in the Gaming queue** — use a separate queue
3. **Keep MSS clamping** at 1360 for Starlink
4. **Always backup** before changes: `/system backup save name=before-change`
5. **DynBW changes Parent only** — never auto-modify child queue limits
6. **Test with ping during changes** — if latency spikes, rollback immediately

---

## 📄 Rollback

If something goes wrong:

```routeros
# 1. Disable adaptive controller
/system scheduler disable [find name~"DynBW" name~"V9"]

# 2. Restore original limits
/queue tree set [find name="Global-Download"] max-limit=250M
/queue tree set [find name="Global-Upload"] max-limit=15M

# 3. Analyze before making more changes
```

---

## 📜 License

MIT License — Use freely, modify as needed.

---

## 🤝 Contributing

Found a bug or have an improvement? Open an issue or PR!

**If this helped your network, give it a ⭐!**

---

*Built with real-world testing on a live 200+ user network by Eng. Hudhaifa Aref*
