#!/bin/bash
RANCHER_LEADER="$(kubectl -n kube-system get lease cattle-controllers -o json | jq -r '.spec.holderIdentity')"
# Display Rancher Pods Information
kubectl get pod -n cattle-system $RANCHER_LEADER -o custom-columns=NAME:.metadata.name,POD-IP:.status.podIP,HOST-IP:.status.hostIP
printf "\n$RANCHER_LEADER is the leader in this Rancher instance\n"
