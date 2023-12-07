#!/bin/bash

# Minimum space needed to run the script (MB)
SPACE="512"

setup() {

  TMPDIR=$(mktemp -d $MKTEMP_BASEDIR)
  techo "Created ${TMPDIR}"

}

disk-space() {

  AVAILABLE=$(df -m ${TMPDIR} | tail -n 1 | awk '{ print $4 }')
  if [ "${AVAILABLE}" -lt "${SPACE}" ]
    then
      techo "${AVAILABLE} MB space free, minimum needed is ${SPACE} MB."
      DISK_FULL=1
  fi

}

verify-access() {

  techo "Verifying cluster access"
  if [[ ! -z $OVERRIDE_KUBECONFIG ]];
  then
    ## Just use the kubeconfig that was set by the user
    KUBECTL_CMD="kubectl --kubeconfig $OVERRIDE_KUBECONFIG"
  elif [[ ! -z $KUBECONFIG ]];
  then
    KUBECTL_CMD="kubectl --kubeconfig $KUBECONFIG"
  else
    ## Giving up
    techo "Could not find a kubeconfig"
  fi
  if ! ${KUBECTL_CMD} cluster-info >/dev/null 2>&1
  then
    techo "Can not access cluster"
    exit 1
  else
    techo "Cluster access has been verified"
  fi
}

cluster-info() {

  techo "Collecting cluster info"
  mkdir -p $TMPDIR/clusterinfo
  ${KUBECTL_CMD} cluster-info > $TMPDIR/clusterinfo/cluster-info 2>&1
  ${KUBECTL_CMD} cluster-info dump > $TMPDIR/clusterinfo/cluster-info-dump 2>&1
  cat $TMPDIR/clusterinfo/cluster-info-dump 2>&1 | grep '"cluster":' | head -n1 | awk '{print $2}' | tr -d '",' > $TMPDIR/clusterinfo/cluster-name
  ${KUBECTL_CMD} get nodes -o wide > $TMPDIR/clusterinfo/get-node-wide 2>&1
  ## Grabbing longhorn-system items
  mkdir -p $TMPDIR/longhorn-system/
  ${KUBECTL_CMD} get endpoints -n longhorn-system -o wide > $TMPDIR/longhorn-system/get-endpoints 2>&1
  ${KUBECTL_CMD} get deployments -n longhorn-system -o wide > $TMPDIR/longhorn-system/get-deployments 2>&1
  ${KUBECTL_CMD} get cronjob -n longhorn-system -o wide > $TMPDIR/longhorn-system/get-cronjob 2>&1
  ${KUBECTL_CMD} get daemonsets -n longhorn-system -o wide > $TMPDIR/longhorn-system/get-daemonsets 2>&1
  ${KUBECTL_CMD} get configmap -n longhorn-system -o wide > $TMPDIR/longhorn-system/get-configmap 2>&1
  ${KUBECTL_CMD} get ingress -n longhorn-system -o yaml > $TMPDIR/longhorn-system/get-ingress.yaml 2>&1
  ${KUBECTL_CMD} get pods -n longhorn-system -o wide > $TMPDIR/longhorn-system/get-pods 2>&1
  ${KUBECTL_CMD} get svc -n longhorn-system -o yaml > $TMPDIR/longhorn-system/get-svc.yaml 2>&1
}

pod-logs() {
    techo "Collecting pod logs"
    mkdir -p $TMPDIR/podlogs
    ${KUBECTL_CMD} get pods -n longhorn-system -o wide > $TMPDIR/podlogs/get-pods 2>&1
    for pod in $(cat $TMPDIR/podlogs/get-pods | awk '{ print $1 }' | grep -v NAME);
    do
      ${KUBECTL_CMD} logs $pod -n longhorn-system > $TMPDIR/podlogs/$pod.log 2>&1
    done
    rm $TMPDIR/podlogs/get-pods
}

dump-crds() {
  techo "Collecting crds"
  mkdir -p $TMPDIR/crds
  for crd in `${KUBECTL_CMD} get crd | grep 'longhorn.io' | awk '{ print $1 }'`;
  do
    ${KUBECTL_CMD} get $crd -o yaml > $TMPDIR/crds/$crd.yaml 2>&1
    mkdir -p $TMPDIR/crds/${crd}
    for object in `${KUBECTL_CMD} get $crd -o NAME | awk  -F '/' '{ print $2 }'`
    do
      ${KUBECTL_CMD} get $crd $object -o yaml > $TMPDIR/crds/${crd}/${object}.yaml 2>&1
    done
  done
}

watch-logs() {

  techo "Live tailing debug logs from Rancher pods"
  techo "Please use Ctrl+C to finish tailing"
  mkdir -p $TMPDIR/rancher-logs/
  ${KUBECTL_CMD} -n longhorn-system logs -f -l app=rancher -c rancher | tee $TMPDIR/rancher-logs/live-logs

}


pause() {

 read -n1 -rsp $'Press any key once finished logging with debug loglevel, or Ctrl+C to exit and leave debug loglevel enabled... \n'

}

archive() {

  FILEDIR=$(dirname $TMPDIR)
  FILENAME=$(cat $TMPDIR/clusterinfo/cluster-name)
  ##FILENAME="$(kubectl config view -o jsonpath='{.current-context}')-$(date +'%Y-%m-%d_%H_%M_%S').tar"
  tar --create --file ${FILEDIR}/${FILENAME} --directory ${TMPDIR}/ .
  ## gzip separately for Rancher OS
  gzip ${FILEDIR}/${FILENAME}

  techo "Created ${FILEDIR}/${FILENAME}.gz"

}

cleanup() {

  techo "Removing ${TMPDIR}"
  rm -r -f "${TMPDIR}" >/dev/null 2>&1

}

help() {

  echo "Longhorn Pod Collector
  Usage: rancher-pod-collector.sh [ -d <directory> -k KUBECONFIG -t -w -f ]

  All flags are optional

  -d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
  -k    Override the kubeconfig (ex: ~/.kube/custom)
  -t    Enable trace logs
  -w    Live tailing Rancher logs
  -f    Force log collection if the minimum space isn't available"

}

timestamp() {

  date "+%Y-%m-%d %H:%M:%S"

}

techo() {

  echo "$(timestamp): $*"

}

while getopts ":d:k:ftwh" opt; do
  case $opt in
    d)
      MKTEMP_BASEDIR="${OPTARG}/temp.XXXX"
      ;;
    k)
      OVERRIDE_KUBECONFIG="${OPTARG}"
      ;;
    f)
      FORCE=1
      ;;
    t)
      TRACE=1
      ;;
    w)
      WATCH=1
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

setup
disk-space
if [ -n "${DISK_FULL}" ]
  then
    if [ -z "${FORCE}" ]
      then
        techo "Cleaning up and exiting"
        cleanup
        exit 1
      else
        techo "-f (force) used, continuing"
    fi
fi

if [ ! -z "${TRACE}" ]
then
  techo "WARNING: Trace logging has been set. Please confirm that you understand this may capture sensitive information."
  pause
fi
verify-access
cluster-info
pod-logs
dump-crds
archive
cleanup
