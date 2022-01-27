#!/bin/bash
NODE="$(kubectl -n kube-system get endpoints kube-scheduler -o jsonpath='{.metadata.annotations.control-plane\.alpha\.kubernetes\.io/leader}' | jq -r .holderIdentity | sed 's/_[^_]*$//')"
echo "kube-scheduler is the leader on node $NODE"
