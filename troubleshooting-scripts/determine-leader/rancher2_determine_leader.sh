#!/bin/bash
RANCHER_LEADER="$(kubectl -n kube-system get configmap cattle-controllers -o json | jq -r '.metadata.annotations."control-plane.alpha.kubernetes.io/leader"' | jq -r '.holderIdentity')"
# Display Rancher Pods Information
kubectl get pod -n cattle-system $LEADER -o custom-columns=NAME:.metadata.name,POD-IP:.status.podIP,HOST-IP:.status.hostIP
printf "\n$RANCHER_LEADER is the leader in this Rancher instance\n"
