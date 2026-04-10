#!/bin/bash
RANCHER_LEADER="$(kubectl -n kube-system get lease cattle-controllers \
  -o jsonpath='{.spec.holderIdentity}' 2>/dev/null)"

if [ -z "$RANCHER_LEADER" ]; then
  echo "ERROR: Could not determine Rancher leader. Is Rancher running?" >&2
  echo "  Verify the cattle-controllers Lease exists:" >&2
  echo "    kubectl -n kube-system get lease cattle-controllers" >&2
  exit 1
fi

# Display Rancher Pods Information
kubectl get pod -n cattle-system "$RANCHER_LEADER" \
  -o custom-columns=NAME:.metadata.name,POD-IP:.status.podIP,HOST-IP:.status.hostIP

printf "\n%s is the leader in this Rancher instance\n" "$RANCHER_LEADER"
