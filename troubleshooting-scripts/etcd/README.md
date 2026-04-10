# etcd Troubleshooting

Commands for inspecting etcd health, status, and data on RKE2 and k3s clusters.
Verified on RKE2 v1.33.7.

---

## Section 1: Via `kubectl exec` (requires kubeconfig)

Iterate over all etcd pods:

```bash
for etcdpod in $(kubectl -n kube-system get pod -l component=etcd \
  --no-headers -o custom-columns=NAME:.metadata.name); do
  echo "=== $etcdpod ==="
  kubectl -n kube-system exec "$etcdpod" -- etcdctl \
    --cert  /var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
    --key   /var/lib/rancher/rke2/server/tls/etcd/server-client.key \
    --cacert /var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
    COMMAND
done
```

Replace `COMMAND` with any of:
- `check perf`
- `endpoint status --cluster --write-out=table`
- `endpoint health --cluster --write-out=table`
- `member list --write-out=table`
- `alarm list`
- `defrag --cluster`

> **Note:** `curl` is not present in the etcd container since k8s 1.28.
> Use `etcdctl endpoint health` for health checks.
> Use `curl http://127.0.0.1:2381/metrics` from the **host** for metrics (see Section 2).

---

## Section 2: On the etcd host via `crictl exec`

Works on k8s ≥ 1.28 (no `/bin/sh` needed — `crictl exec` runs the binary directly).

### Setup

**RKE2:**

```bash
export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml
CRICTL=/var/lib/rancher/rke2/bin/crictl
CERT_DIR=/var/lib/rancher/rke2/server/tls/etcd
```

**k3s:**

```bash
export CRI_CONFIG_FILE=/var/lib/rancher/k3s/agent/etc/crictl.yaml
CRICTL=/var/lib/rancher/k3s/data/current/bin/crictl
CERT_DIR=/var/lib/rancher/k3s/server/tls/etcd
# Alternative: k3s etcdctl (no crictl wrapper needed)
```

**Common variables:**

```bash
ETCD_CONTAINER=$($CRICTL ps --label io.kubernetes.container.name=etcd --quiet | head -1)
CERT="$CERT_DIR/server-client.crt"
KEY="$CERT_DIR/server-client.key"
CA="$CERT_DIR/server-ca.crt"
```

### etcdctl commands

All commands follow this pattern:

```bash
$CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  COMMAND
```

Replace `COMMAND` with:

```bash
# Performance check
check perf

# Endpoint status (all members)
endpoint status --cluster --write-out=table

# Endpoint health (all members)
endpoint health --cluster --write-out=table

# Member list
member list --write-out=table

# List alarms
alarm list

# Defragment all members
defrag --cluster
```

### Compact with auto-revision

```bash
REV=$($CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  endpoint status --write-out fields | grep "^Revision" | cut -d: -f2 | tr -d ' ')

$CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  compact "$REV"
```

### Metrics and health (port 2381, plain HTTP — no certs)

Port 2381 is etcd's `--listen-metrics-urls` and serves plain HTTP with no TLS.
Port 2379 is gRPC-only and cannot be used with plain `curl`.

```bash
# Health
curl -sL http://127.0.0.1:2381/health

# Metrics
curl -sL http://127.0.0.1:2381/metrics

# Liveness / Readiness
curl -sL http://127.0.0.1:2381/livez
curl -sL http://127.0.0.1:2381/readyz
```

### Member connectivity check

Use `etcdctl` — the curl loop on port 2379 does not work (gRPC-only port):

```bash
$CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  endpoint health --cluster --write-out=table
```

### Watch etcd changes

```bash
$CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  watch --prefix /registry
```

### Query etcd keys

```bash
$CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  get /registry --prefix=true --keys-only
```

### Key count per resource type (find bloated resources)

```bash
$CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  get /registry --prefix=true --keys-only | grep -v '^$' | \
  awk -F'/' '{ if ($3 ~ /cattle.io/) {h[$3"/"$4]++} else { h[$3]++ }} \
  END { for(k in h) print h[k], k }' | sort -nr
```

### Enable/disable debug logging

```bash
# Enable
$CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  --endpoints https://127.0.0.1:2379 \
  log-level debug

# Disable
$CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  --endpoints https://127.0.0.1:2379 \
  log-level info
```

---

## Quick script

`check-endpoints.sh` auto-detects RKE2 or k3s and runs health + status + members + alarms:

```bash
curl -s https://raw.githubusercontent.com/rancherlabs/support-tools/master/troubleshooting-scripts/etcd/check-endpoints.sh | sudo bash
```

---

## Log message reference

| Message | Meaning |
|---------|---------|
| `health check for peer xxx could not connect: dial tcp IP:2380` | etcd container not running on that peer, or port 2380 blocked |
| `xxx is starting a new election at term x` | Cluster lost quorum; majority of etcd nodes down |
| `connection error: i/o timeout … 0.0.0.0:2379` | Host firewall blocking etcd client port |
| `rafthttp: request cluster ID mismatch` | Node trying to join wrong cluster — remove and re-add |
| `rafthttp: failed to find member` | Stale cluster state in `/var/lib/etcd` — remove, clean, and re-add |

---

## Section 3: Deprecated — RKE1

> RKE1 reached end-of-life. Commands below are preserved for reference only.

```bash
# List members
docker exec etcd etcdctl member list

# Print cert env vars
docker exec etcd printenv ETCDCTL_CERT_FILE ETCDCTL_KEY_FILE ETCDCTL_CA_FILE

# Cluster health (etcd v2)
docker exec etcd etcdctl cluster-health

# Endpoint health (etcd v3)
docker exec etcd etcdctl endpoint health

# Check endpoint connectivity (curl loop via appropriate/curl image)
for endpoint in $(docker exec etcd /bin/sh -c "etcdctl member list | cut -d, -f5"); do
  echo "Validating connection to ${endpoint}/health"
  docker run --net=host \
    -v $(docker inspect kubelet --format '{{ range .Mounts }}{{ if eq .Destination "/etc/kubernetes" }}{{ .Source }}{{ end }}{{ end }}')/ssl:/etc/kubernetes/ssl:ro \
    appropriate/curl -s -w "\n" \
    --cacert $(docker exec etcd printenv ETCDCTL_CACERT) \
    --cert   $(docker exec etcd printenv ETCDCTL_CERT) \
    --key    $(docker exec etcd printenv ETCDCTL_KEY) \
    "${endpoint}/health"
done

# Enable debug logging (RKE1)
curl -XPUT -d '{"Level":"DEBUG"}' \
  --cacert $(docker exec etcd printenv ETCDCTL_CACERT) \
  --cert   $(docker exec etcd printenv ETCDCTL_CERT) \
  --key    $(docker exec etcd printenv ETCDCTL_KEY) \
  https://localhost:2379/config/local/log

# Disable debug logging (RKE1)
curl -XPUT -d '{"Level":"INFO"}' \
  --cacert $(docker exec etcd printenv ETCDCTL_CACERT) \
  --cert   $(docker exec etcd printenv ETCDCTL_CERT) \
  --key    $(docker exec etcd printenv ETCDCTL_KEY) \
  https://localhost:2379/config/local/log

# Get metrics (RKE1)
curl -X GET \
  --cacert $(docker exec etcd printenv ETCDCTL_CACERT) \
  --cert   $(docker exec etcd printenv ETCDCTL_CERT) \
  --key    $(docker exec etcd printenv ETCDCTL_KEY) \
  https://localhost:2379/metrics
```
