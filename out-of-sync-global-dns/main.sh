#!/bin/bash

setup() {
  while getopts ":s:fh" opt; do
  case $opt in
    s)
      SLEEP="-s ${OPTARG}"
      ;;
    h)
      help && exit 0
      ;;
    :)
      techo "Option -$OPTARG requires an argument."
      exit 1
      ;;
    *)
      help && exit 0
  esac
  done

  if [[ -z $SLEEP ]]
  then
    SLEEP=360
  fi
}
verify-settings() {
  if [[ -z $CATTLE_SERVER ]] || [[ -z $CATTLE_ACCESS_KEY ]] || [[ -z $CATTLE_SECRET_KEY ]]
  then
    echo "CRITICAL - CATTLE_SERVER, CATTLE_ACCESS_KEY, and CATTLE_SECRET_KEY must be configured"
    exit 1
  fi
}
setup-tmp-dir() {
  TMPDIR=$(mktemp -d /tmp)
  if [[ ! -d $TMPDIR ]]
  then
    echo "CRITICAL: Creating TMPDIR"
    exit 2
  else
    echo "Created ${TMPDIR}"
  fi
}
cleanup-tmp-dir() {
  echo "Cleaning up TMPDIR"
  rm -rf ${TMPDIR}
  if [[ -d $TMPDIR ]]
  then
    echo "CRITICAL: TMPDIR wasn't deleted"
    exit 2
  fi
}
get-clusters() {
  clusters=`curl -k -s "https://${CATTLE_SERVER}/v3/clusters?limit=-1&sort=name" -u "${CATTLE_ACCESS_KEY}:${CATTLE_SECRET_KEY}" -H 'content-type: application/json' |jq -r .data[].id`
  RESULT=$?
  if [ $RESULT -eq 0 ];
  then
    echo "CRITICAL: Getting a cluster list failed"
    exit 2
  fi
}
build-kubeconfig() {
  mkdir -p ${TMPDIR}/kubeconfig
  for cluster in $clusters
  do
    curl -k -s -u "${CATTLE_ACCESS_KEY}:${CATTLE_SECRET_KEY}" https://${CATTLE_SERVER}/v3/clusters/${cluster}?action=generateKubeconfig -X POST -H 'content-type: application/json' | jq -r .config > ${TMPDIR}/kubeconfig/${cluster}
  done
}
get-globaldnslist() {
  echo "Getting GlobalDns records..."
  mkdir -p ${TMPDIR}/globaldnses
  GlobalDnsList=`kubectl --kubeconfig ${TMPDIR}/kubeconfig/local get globaldnses.management.cattle.io -n cattle-global-data -o name | awk -F '/' '{print $2}'`
  for GlobalDns in $GlobalDnsList
  do
    kubectl --kubeconfig ${TMPDIR}/kubeconfig/local get globaldnses.management.cattle.io -n cattle-global-data ${GlobalDns} -o json > ${TMPDIR}/globaldnses/${GlobalDns}
  done
}
scan-ingresses() {
  cluster=$1
  echo "Working on cluster ${cluster}"
  mkdir -p ${TMPDIR}/data/${cluster}
  namespaces=`kubectl --kubeconfig ${TMPDIR}/kubeconfig/${cluster} get namespace -o name | awk -F '/' '{print $2}'`
  for namespace in $namespaces
  do
    echo "Working on namespace ${namespace}"
    projectId=`kubectl --kubeconfig ${TMPDIR}/kubeconfig/${cluster} get ${namespace} -o json | jq ' .metadata.annotations | with_entries(select(.key == "field.cattle.io/projectId")) ' | jq .[] | tr -d '"'`
    mkdir -p ${TMPDIR}/data/${cluster}/${namespace}
    ingresses=`kubectl --kubeconfig ${TMPDIR}/kubeconfig/${cluster} -n ${namespace} get ingress -o name | awk -F '/' '{print $2}'`
    for ingress in $ingresses
    do
      globalDNShostname=`kubectl --kubeconfig ${TMPDIR}/kubeconfig/${cluster} get ingress ${ingress} -o json | jq ' .metadata.annotations | with_entries(select(.key == "rancher.io/globalDNS.hostname")) ' | jq .[] | tr -d '"'`
      echo "Searching for globaldnses.management.cattle.io record"
      cd ${TMPDIR}/globaldnses
      gdcandidates=`grep -R -l "${projectId}" .`
      unset ghname
      for gdcandidate in $gdcandidates
      do
        if grep -i "${globalDNShostname}" ${gdcandidate}
        then
          ghname=${gdcandidate}
        fi
      done
      if [[ -z $ghname ]]
      then
        echo "CRITICAL: Could not find globaldnses for ingress ${ingress} in namespace ${namespace} in cluster $cluster"
      else
        echo "Checking IPs..."
        upstreamips=`kubectl --kubeconfig ${TMPDIR}/kubeconfig/local -n cattle-global-data get globaldnses.management.cattle.io ${ghname} -o json | jq -r .status.endpoints | jq .[] | tr -d '"' | sort`
        downstreamips=`kubectl --kubeconfig ${TMPDIR}/kubeconfig/${cluster} -n ${namespace} get ingress ${ingress} -o json | jq -r .status.loadBalancer.ingress | grep 'ip' | awk '{print $2}' | tr -d '"' | sort`
        if ! diff <(echo "$upstreamips") <(echo "$downstreamips")
        then
          echo "CRITICAL: We have detected a difference between the ingress IPs and the globalDNS record for ingress ${ingress} in namespace ${namespace} in cluster $cluster"
          echo "::Upstream::"
          kubectl --kubeconfig ${TMPDIR}/kubeconfig/local -n cattle-global-data get globaldnses.management.cattle.io ${ghname} -o json | jq -r .status.endpoints
          echo "::Downstream::"
          kubectl --kubeconfig ${TMPDIR}/kubeconfig/${cluster} -n ${namespace} get ingress ${ingress} -o json | jq -r .status.loadBalancer.ingress
        else
          eco "OK: The IPs for ingress ${ingress} in namespace ${namespace} in cluster $cluster look to be correct"
        fi
      fi
    done
  done
}

echo "Starting..."
setup
verify-settings
while true
do
  setup-tmp-dir
  get-clusters
  build-kubeconfig
  get-globaldnslist
  for cluster in $clusters
  do
    scan-ingresses $cluster
  done
  cleanup-tmp-dir
  sleep ${SLEEP}
done
