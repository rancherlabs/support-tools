#!/bin/bash
LEADER="$(kubectl -n kube-system get configmap cattle-controllers -o jsonpath='{.metadata.annotations.control-plane\.alpha\.kubernetes\.io/leader}' | jq . 2>/dev/null | grep 'holderIdentity' | awk '{print $2}' | tr -d ",\"" | awk -F '_' '{print $1}')"
echo "$LEADER is the leader in this Rancher instance"
