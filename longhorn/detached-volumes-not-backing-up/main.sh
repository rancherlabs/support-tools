#!/bin/bash

if [[ -z $LoopSleep ]]
then
  LoopSleep=60
fi
if [[ -z $LonghornNamespace ]]
then
  LonghornNamespace="longhorn-system"
fi
if [[ -z $ResetTrigger ]]
then
  ResetTrigger=50
fi

while true
do

for cronjobname in `kubectl -n $LonghornNamespace get cronjobs -o name | awk -F'/' '{print $2}'`
do
  echo -n "Checking on cronjob $cronjobname ... "
  cronjobstate=`kubectl -n $LonghornNamespace get cronjob $cronjobname -o=jsonpath='{.spec.suspend}'`
  volumename=`kubectl -n $LonghornNamespace get cronjob $cronjobname -o custom-columns=CONTROLLER:.metadata.ownerReferences[].name --no-headers`
  volumestate=`kubectl -n $LonghornNamespace get volumes.longhorn.io $volumename -o=jsonpath='{.status.state}'`
  if [[ "$cronjobstate" == "true" ]] && [[ "$volumestate" == "attached" ]]
  then
    echo "Bad"
    echo "Found broken job, the cronjob is suspend but the volume is currently attached"
    echo "=========================Dumping debug data - start ================================"
    echo "Status of cronjob: $cronjobstate"
    echo "Longhorn volume name: $volumename"
    echo "Longhorn volume state: $volumestate"
    kubectl -n $LonghornNamespace get cronjob $cronjobname -o json
    kubectl -n $LonghornNamespace get volumes.longhorn.io $volumename -o json
    echo "=========================Dumping debug data - end   ================================"
    echo "Patching..."
    kubectl -n $LonghornNamespace patch cronjobs $cronjobname -p "{\"spec\" : {\"suspend\" : false }}"
  fi
  startingDeadlineSeconds=`kubectl -n ${LonghornNamespace} get cronjob ${cronjob} -o=jsonpath='{.spec.startingDeadlineSeconds}'`
  if [[ ! $startingDeadlineSeconds == 'null' ]] && [[ $startingDeadlineSeconds -gt $ResetTrigger ]]
  then
    echo "Bad"
    echo "Found job with high startingDeadlineSeconds, need to patch back to 1"
    echo "=========================Dumping debug data - start ================================"
    echo "startingDeadlineSeconds: $startingDeadlineSeconds"
    kubectl -n $LonghornNamespace get cronjob $cronjobname -o json
    echo "=========================Dumping debug data - end   ================================"
    echo "Patching..."
    kubectl -n ${LonghornNamespace} patch cronjob ${cronjobname} -p '{"spec":{"startingDeadlineSeconds":1}}'
  fi
echo "Sleeping..."
sleep $LoopSleep
done
