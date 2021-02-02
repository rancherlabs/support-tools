#!/bin/bash
SPACE="512"
TIMEOUT="60"

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
    RANCHER_POD=$(kubectl --kubeconfig $OVERRIDE_KUBECONFIG -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=id:metadata.name | head -n1)
    KUBECTL_CMD="kubectl --kubeconfig $OVERRIDE_KUBECONFIG -n cattle-system exec -c rancher ${RANCHER_POD} -- kubectl"
  elif [[ ! -z $KUBERNETES_PORT ]] || [[ ! -z $KUBECONFIG ]];
  then
    ## We are inside the k8s cluster or we're using the local kubeconfig
    RANCHER_POD=$(kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=id:metadata.name | head -n1)
    KUBECTL_CMD="kubectl -n cattle-system exec -c rancher ${RANCHER_POD} -- kubectl"
  elif $(command -v k3s >/dev/null 2>&1)
  then
    ## We are on k3s node
    KUBECTL_CMD="k3s kubectl"
  elif $(command -v docker >/dev/null 2>&1)
  then
    DOCKER_ID=$(docker ps | grep "k8s_rancher_rancher" | cut -d' ' -f1 | head -1)
    KUBECTL_CMD="docker exec ${DOCKER_ID} kubectl"
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
  ${KUBECTL_CMD} get nodes -o wide > $TMPDIR/clusterinfo/get-node-wide 2>&1
  ## Grabbing cattle-system items
  mkdir -p $TMPDIR/cattle-system/
  ${KUBECTL_CMD} get pods -n cattle-system -o wide > $TMPDIR/cattle-system/get-pods 2>&1
  ${KUBECTL_CMD} get svc -n cattle-system -o wide > $TMPDIR/cattle-system/get-svc 2>&1
  ${KUBECTL_CMD} get endpoints -n cattle-system -o wide > $TMPDIR/cattle-system/get-endpoints 2>&1
  ## Grabbing kube-system items
  mkdir -p $TMPDIR/kube-system/
  ${KUBECTL_CMD} get configmap -n cattle-system cattle-controllers -o yaml > $TMPDIR/kube-system/get-configmap-cattle-controllers.yaml 2>&1

}

enable-debug() {

  techo "Enabling debug for Rancher pods"
  for POD in $(${KUBECTL_CMD} get pods -n cattle-system -l app=rancher --no-headers | awk '{print $1}');
  do
    if [ ! -z "${TRACE}" ]
    then
      techo "Pod: $POD `${KUBECTL_CMD} exec -n cattle-system -c rancher $POD -- loglevel --set trace`"
    else
      techo "Pod: $POD `${KUBECTL_CMD} exec -n cattle-system -c rancher $POD -- loglevel --set debug`"
    fi
  done

}

disable-debug() {

  techo "Disabling debug for Rancher pods"
  for POD in $(${KUBECTL_CMD} get pods -n cattle-system -l app=rancher --no-headers | awk '{print $1}');
  do
    techo "Pod: $POD `${KUBECTL_CMD} exec -n cattle-system -c rancher $POD -- loglevel --set debug`"
  done

}

capture-logs() {

  techo "Capturing debug logs from Rancher pods"
  mkdir -p $TMPDIR/rancher-logs/
  for POD in $(${KUBECTL_CMD} get pods -n cattle-system -l app=rancher --no-headers | awk '{print $1}');
  do
    techo "Pod: $POD"
    ${KUBECTL_CMD} -n cattle-system logs -c rancher $POD > $TMPDIR/rancher-logs/$POD
  done

}

pause(){
 read -n1 -rsp $'Press any key to continue or Ctrl+C to exit...\n'
}

archive() {

  FILEDIR=$(dirname $TMPDIR)
  FILENAME="$(hostname)-$(date +'%Y-%m-%d_%H_%M_%S').tar"
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

  echo "Rancher Pod Collector
  Usage: rancher-pod-collector.sh [ -d <directory> -r <container runtime> -k KUBECONFIG -t -f ]

  All flags are optional

  -d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
  -r    Override container runtime if not automatically detected (docker|k3s)
  -k    Override the kubeconfig (ex: ~/.kube/custom)
  -t    Enable tracve logs
  -f    Force log collection if the minimum space isn't available"

}

timestamp() {

  date "+%Y-%m-%d %H:%M:%S"

}

techo() {

  echo "$(timestamp): $*"

}

while getopts ":d:r:k:fth" opt; do
  case $opt in
    d)
      MKTEMP_BASEDIR="-p ${OPTARG}"
      ;;
    r)
      RUNTIME_FLAG="${OPTARG}"
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
enable-debug
pause
disable-debug
capture-logs
archive
cleanup
