#!/bin/bash

echo "Getting IPs from endpoint..."
EndPointIPs=`kubectl get endpoints kubernetes -o json | jq .subsets[].addresses[].ip | tr -d '"'`

for EndPointIP in $EndPointIPs
do
  if kubectl get nodes --selector=node-role.kubernetes.io/controlplane=true -o jsonpath={.items[*].status.addresses[?\(@.type==\"InternalIP\"\)].address} | grep $EndPointIP > /dev/null
  then
    echo "Good - $EndPointIP"
  else
    echo "Problem - $EndPointIP"
  fi
done
