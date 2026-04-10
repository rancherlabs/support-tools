#!/bin/bash
# Check kube-apiserver connectivity to etcd on RKE2 or k3s clusters.
# Must be run as root on a server/control-plane node.
#
# Usage: bash check_apiserver-to-etcd.sh

set -euo pipefail

detect_distro() {
  if [ -d /var/lib/rancher/rke2/server/tls/etcd ]; then
    echo "rke2"
  elif [ -d /var/lib/rancher/k3s/server/tls/etcd ]; then
    echo "k3s"
  else
    echo "unknown"
  fi
}

DISTRO=$(detect_distro)

if [ "$DISTRO" = "rke2" ]; then
  export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml
  CRICTL=/var/lib/rancher/rke2/bin/crictl
  CERT_DIR=/var/lib/rancher/rke2/server/tls/etcd
elif [ "$DISTRO" = "k3s" ]; then
  export CRI_CONFIG_FILE=/var/lib/rancher/k3s/agent/etc/crictl.yaml
  CRICTL=/var/lib/rancher/k3s/data/current/bin/crictl
  CERT_DIR=/var/lib/rancher/k3s/server/tls/etcd
else
  echo "ERROR: Could not detect RKE2 or k3s installation." >&2
  exit 1
fi

ETCD_CONTAINER=$($CRICTL ps --label io.kubernetes.container.name=etcd --quiet 2>/dev/null | head -1)

if [ -z "$ETCD_CONTAINER" ]; then
  echo "ERROR: No running etcd container found." >&2
  exit 1
fi

CERT="$CERT_DIR/server-client.crt"
KEY="$CERT_DIR/server-client.key"
CA="$CERT_DIR/server-ca.crt"

echo "=== etcd member list (distro: $DISTRO) ==="
$CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  member list --write-out=table

echo ""
echo "=== etcd endpoint status ==="
$CRICTL exec "$ETCD_CONTAINER" etcdctl \
  --cert "$CERT" --key "$KEY" --cacert "$CA" \
  endpoint status --cluster --write-out=table
