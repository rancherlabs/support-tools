#!/bin/bash
# Find the current kube-scheduler leader.
# Uses Lease-based leader election (RKE2, k3s, k8s >= 1.20).
# Verified working on RKE2 v1.33.7.
#
# Usage: bash find-leader.sh

NODE=$(kubectl -n kube-system get lease kube-scheduler \
  -o jsonpath='{.spec.holderIdentity}' 2>/dev/null | sed 's/_[^_]*$//')

if [ -z "$NODE" ]; then
  echo "ERROR: Could not determine kube-scheduler leader." >&2
  echo "  Verify the kube-scheduler Lease exists:" >&2
  echo "    kubectl -n kube-system get lease kube-scheduler" >&2
  exit 1
fi

echo "kube-scheduler leader: $NODE"
