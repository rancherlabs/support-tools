# RKE2 Quick Reference

Quick reference for common RKE2 operations on server/control-plane nodes.

---

## Install

```bash
curl -sL https://get.rke2.io | sh
```

Select a channel:

```bash
# Stable (default)
curl -sL https://get.rke2.io | INSTALL_RKE2_CHANNEL=stable sh

# Latest
curl -sL https://get.rke2.io | INSTALL_RKE2_CHANNEL=latest sh

# Pin to a specific version
curl -sL https://get.rke2.io | INSTALL_RKE2_VERSION=v1.27.5+rke2r1 sh
```

Enable and start:

```bash
systemctl enable --now rke2-server
```

---

## Binary Locations

All binaries live under `/var/lib/rancher/rke2/bin/`:

```
containerd
containerd-shim
containerd-shim-runc-v1
containerd-shim-runc-v2
crictl
ctr
kubectl
kubelet
runc
```

> **Note:** `etcdctl` is **not** present in this directory on RKE2 v1.31+.
> It lives only inside the etcd container. Access it via `crictl exec` — see [etcd/README.md](../etcd/README.md).

---

## kubeconfig

Via environment variable:

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/var/lib/rancher/rke2/bin/kubectl get nodes
```

Via inline flag (no env required):

```bash
/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes
```

Add to your shell profile (persistent):

```bash
echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> ~/.bashrc
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc
```

---

## containerd

Socket location: `/run/k3s/containerd/containerd.sock`

---

## ctr

```bash
/var/lib/rancher/rke2/bin/ctr \
  --address /run/k3s/containerd/containerd.sock \
  --namespace k8s.io \
  container ls
```

List images:

```bash
/var/lib/rancher/rke2/bin/ctr \
  --address /run/k3s/containerd/containerd.sock \
  --namespace k8s.io \
  image ls
```

---

## crictl

Three equivalent ways to invoke crictl:

**1. Via environment variable (recommended):**

```bash
export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml
/var/lib/rancher/rke2/bin/crictl ps
```

**2. Via config flag:**

```bash
/var/lib/rancher/rke2/bin/crictl \
  --config /var/lib/rancher/rke2/agent/etc/crictl.yaml ps
```

**3. Via socket flag:**

```bash
/var/lib/rancher/rke2/bin/crictl \
  --runtime-endpoint unix:///run/k3s/containerd/containerd.sock ps -a
```

Common crictl commands:

```bash
# List running containers
/var/lib/rancher/rke2/bin/crictl ps

# List all containers (including stopped)
/var/lib/rancher/rke2/bin/crictl ps -a

# List pods
/var/lib/rancher/rke2/bin/crictl pods

# Pull/inspect images
/var/lib/rancher/rke2/bin/crictl images
/var/lib/rancher/rke2/bin/crictl inspecti <image-id>

# Exec into a container (no shell required)
/var/lib/rancher/rke2/bin/crictl exec <container-id> <command>

# Container logs
/var/lib/rancher/rke2/bin/crictl logs <container-id>
```

---

## Logging

```bash
# Server service journal
journalctl -f -u rke2-server

# Agent service journal
journalctl -f -u rke2-agent

# containerd log
/var/lib/rancher/rke2/agent/containerd/containerd.log

# kubelet log
/var/lib/rancher/rke2/agent/logs/kubelet.log
```

---

## Systemd Service Files

| File | Path |
|------|------|
| Server service unit | `/usr/local/lib/systemd/system/rke2-server.service` |
| Agent service unit | `/usr/local/lib/systemd/system/rke2-agent.service` |
| Server env override | `/etc/default/rke2-server` |
| Agent env override | `/etc/default/rke2-agent` |

Use the env override files to set or override RKE2 environment variables without editing the unit file directly (survives upgrades).

---

## Distribution Contents

Scripts and configs installed alongside the RKE2 binary:

| File | Location | Purpose |
|------|----------|---------|
| `rke2-killall.sh` | `/usr/local/bin/rke2-killall.sh` | Stop all RKE2 processes and unmount volumes |
| `rke2-uninstall.sh` | `/usr/local/bin/rke2-uninstall.sh` | Fully remove RKE2 from a Linux node |
| `rke2-cis-sysctl.conf` | `/usr/local/lib/sysctl.d/60-rke2-cis.conf` | Kernel parameter overrides for CIS hardening |

> **Warning:** `rke2-uninstall.sh` removes all RKE2 data and config — run only when decommissioning a node.

---

## k3s Equivalents

| Resource | RKE2 | k3s |
|----------|------|-----|
| TLS certs dir | `/var/lib/rancher/rke2/server/tls/` | `/var/lib/rancher/k3s/server/tls/` |
| kubeconfig | `/etc/rancher/rke2/rke2.yaml` | `/etc/rancher/k3s/k3s.yaml` |
| crictl binary | `/var/lib/rancher/rke2/bin/crictl` | `/var/lib/rancher/k3s/data/current/bin/crictl` |
| crictl config | `/var/lib/rancher/rke2/agent/etc/crictl.yaml` | `/var/lib/rancher/k3s/agent/etc/crictl.yaml` |
| containerd socket | `/run/k3s/containerd/containerd.sock` | `/run/k3s/containerd/containerd.sock` |
| Service name | `rke2-server` | `k3s` |
| etcdctl shortcut | *(use crictl exec)* | `k3s etcdctl` |
