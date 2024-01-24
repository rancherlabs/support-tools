#!/bin/bash

verify-settings() {
  #echo "CATTLE_SERVER: $CATTLE_SERVER"
  #echo "CATTLE_ACCESS_KEY: $CATTLE_ACCESS_KEY"
  #echo "CATTLE_SECRET_KEY: $CATTLE_SECRET_KEY"
  if [[ -z $CATTLE_SERVER ]] || [[ -z $CATTLE_ACCESS_KEY ]] || [[ -z $CATTLE_SECRET_KEY ]]
  then
    echo "CRITICAL - CATTLE_SERVER, CATTLE_ACCESS_KEY, and CATTLE_SECRET_KEY must be configured"
    exit 1
  fi
}

get-clusters() {
  clusters=`curl -k -s "https://${CATTLE_SERVER}/v3/clusters?limit=-1&sort=name" -u "${CATTLE_ACCESS_KEY}:${CATTLE_SECRET_KEY}" -H 'content-type: application/json' |jq -r .data[].id`
  RESULT=$?
  if [ ! $RESULT -eq 0 ];
  then
    echo "CRITICAL: Getting a cluster list failed"
    exit 2
  fi
}

searching() {
  mkdir --p ~/.kube/
  for cluster in $clusters
  do
    #echo "Cluster: $cluster"
    clusterName=`curl -k -s -u "${CATTLE_ACCESS_KEY}:${CATTLE_SECRET_KEY}" https://${CATTLE_SERVER}/v3/clusters/${cluster} -X GET -H 'content-type: application/json' | jq -r .name`
    curl -k -s -u "${CATTLE_ACCESS_KEY}:${CATTLE_SECRET_KEY}" https://${CATTLE_SERVER}/v3/clusters/${cluster}?action=generateKubeconfig -X POST -H 'content-type: application/json' | jq -r .config > ~/.kube/${clusterName}
    for machine in `kubectl get nodes.management.cattle.io -n "$cluster" -o NAME | awk -F'/' '{print $2}'`
    do
      #echo "Machine: $machine"
      machineHostname=`kubectl get nodes.management.cattle.io -n "$cluster" "$machine" -o json | jq -r .spec.requestedHostname`
      kubectl --kubeconfig ~/.kube/${clusterName} get nodes $machineHostname > /dev/null 2> /dev/null
      RESULT=$?
      if [ ! $RESULT -eq 0 ];
      then
        echo "CRITICAL: $machine was matched with $machineHostname but could not be found in $clusterName / $cluster"
      else
        echo "OK: $machine was matched with $machineHostname in $clusterName / $cluster"
      fi
    done
  done
}

usage() {
  echo "Usage: $0 [ -n NAME ] [ -t TIMES ]" 1>&2
}

exit_abnormal() {                         # Function: Exit with error.
  usage
  exit 1
}

while getopts ":u:a:s:" options; do
  case "${options}" in
    u)
      CATTLE_SERVER=${OPTARG}
      ;;
    a)
      CATTLE_ACCESS_KEY=${OPTARG}
      ;;
    s)
      CATTLE_SECRET_KEY=${OPTARG}
      ;;
    :)                                    # If expected argument omitted:
      echo "Error: -${OPTARG} requires an argument."
      exit_abnormal                       # Exit abnormally.
      ;;
    *)                                    # If unknown (any other) option:
      exit_abnormal                       # Exit abnormally.
      ;;
  esac
done

verify-settings
get-clusters
searching
