#!/bin/bash

if [[ -z $LOOP_SLEEP ]]
then
  LOOP_SLEEP=60
fi
if [[ -z $LONGHORN_NAMESPACE ]]
then
  LONGHORN_NAMESPACE="longhorn-system"
fi
if [[ -z $AlertOnly ]]
then
  AlertOnly="False"  
fi

while true
do

for volume in `kubectl -n $LONGHORN_NAMESPACE get volumes.longhorn.io -o NAME| awk -F'/' '{print $2}'`
do
  if [[ ! -z $Debug ]]; then echo "Checking $volume"; fi
  state=`kubectl -n $LONGHORN_NAMESPACE get volumes.longhorn.io $volume -o=jsonpath='{.status.state}'`
  if [[ "$state" == "attached" ]]
  then
    if [[ ! -z $Debug ]]; then echo "Volume is attached, skipping"; fi
    echo "OK: $volume is attached"
  else
    if [[ ! -z $Debug ]]; then echo "Volume is not attached, need to check"; fi
    nodeid=`kubectl -n $LONGHORN_NAMESPACE get volumes.longhorn.io $volume -o=jsonpath='{.spec.nodeID}'`
    if [[ -z $nodeid ]]
    then
      echo "OK: $volume nodeID is Unset"
    else
      if [[ $AlertOnly == "True" ]]
      then
        echo "CRITICAL: $volume nodeID is $nodeid"
      else
        if [[ ! -z $Debug ]]; then echo "Volume is not attached but has a nodeID, trying to fix it"; fi
        if kubectl -n $LONGHORN_NAMESPACE patch volumes.longhorn.io $volume --type='json' -p='[{"op": "replace", "path": "/spec/nodeID", "value":""}]'
        then 
          if [[ ! -z $Debug ]]; then echo "Patch command was successful, rechecking"; fi
          nodeid=`kubectl -n $LONGHORN_NAMESPACE get volumes.longhorn.io $volume -o=jsonpath='{.spec.nodeID}'`
          if [[ -z $nodeid ]]
          then
            echo "WARNING: $volume was patched and nodeID is now Unset"
          else
            echo "CRITICAL: $volume was patched but nodeID is still set"
          fi
        else
          echo "CRITICAL: $volume failed to patch"
        fi
      fi
    fi
  fi
done

if [[ ! -z $Debug ]]; then echo "Sleeping..."; fi
sleep $LOOP_SLEEP
done
