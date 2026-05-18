# RKE2-Pre-Join-Node-Checker

## Overview

RKE2 networking issues are commonly caused by host-level misconfigurations such as:

- `firewalld` interfering with iptables rules
- `NetworkManager` manipulating CNI interfaces
- `nm-cloud-setup` altering routing tables
- Missing kernel modules or sysctl settings
- Missing `iptables` dependencies

These issues typically appear **after a node successfully joins**, leading to situations where:

- Nodes are `NotReady`
- CoreDNS is stuck or crashlooping
- Pod-to-pod networking fails
- Services are unreachable

This tool provides a **pre-flight validation check** to detect these issues **before node join**, preventing a large class of networking-related failures.

---

## What It Checks

### Services
- `firewalld` (must be disabled for Canal)
- `NetworkManager` configuration (must ignore CNI interfaces)
- `nm-cloud-setup` (must be disabled)

### Networking & Sysctl
- IPv4 forwarding (`net.ipv4.conf.all.forwarding=1`)
- IPv6 forwarding (optional, for dual-stack)
- Bridge netfilter settings:
  - `net.bridge.bridge-nf-call-iptables`
  - `net.bridge.bridge-nf-call-ip6tables`

### Dependencies
- `iptables` / `xtables-nft`

### Kernel Modules
- `br_netfilter`
- `overlay`
- `vxlan` (for VXLAN-based CNIs like Canal)

---

## Usage

```bash
chmod +x rke2-prejoin-check.sh
sudo ./rke2-prejoin-check.sh
