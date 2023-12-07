#!/bin/bash

if [[ -z $LoopSleep ]]
then
  LoopSleep=60
fi

echo "Starting checks..."
for clusterid in `kubectl get clusters.management.cattle.io -o name | awk -F '/' '{print $2}' | grep -v local`;
do
  echo "Checking cluster $clusterid"
  status=`kubectl get clusters.management.cattle.io ${clusterid} -o json | jq '.status.conditions[] | select(.type == "Connected") | .status' | tr -d '"'`
  if [ "$status" != "True" ]; then
    echo "Cluster $clusterid is not connected"
    kubectl patch clusters.management.cattle.io ${clusterid} -p '{"status":{"agentImage":"dummy"}}' --type merge
  else
    echo "Cluster $clusterid is connected"
  fi
  echo "Sleeping..."
   sleep $LoopSleep
done
