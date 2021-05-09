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
    KUBECTL_CMD="kubectl"
  elif [[ ! -z $KUBERNETES_PORT ]];
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
  ${KUBECTL_CMD} get nodes -o wide > $TMPDIR/clusterinfo/get-node-wide 2>&1
  ${KUBECTL_CMD} cluster-info dump -o yaml -n cattle-system --log-file-max-size 500 --output-directory $TMPDIR/clusterinfo/cluster-info-dump
  ## Grabbing cattle-system items
  mkdir -p $TMPDIR/cattle-system/
  ${KUBECTL_CMD} get endpoints -n cattle-system -o wide > $TMPDIR/cattle-system/get-endpoints 2>&1
  ${KUBECTL_CMD} get ingress -n cattle-system -o yaml > $TMPDIR/cattle-system/get-ingress.yaml 2>&1
  ${KUBECTL_CMD} get pods -n cattle-system -o wide > $TMPDIR/cattle-system/get-pods 2>&1
  ${KUBECTL_CMD} get svc -n cattle-system -o yaml > $TMPDIR/cattle-system/get-svc.yaml 2>&1
  ## Grabbing kube-system items
  mkdir -p $TMPDIR/kube-system/
  ${KUBECTL_CMD} get configmap -n kube-system cattle-controllers -o yaml > $TMPDIR/kube-system/get-configmap-cattle-controllers.yaml 2>&1
  ## Grabbing cluster configuration
  mkdir -p $TMPDIR/clusters
  ${KUBECTL_CMD} get clusters.management.cattle.io -A > $TMPDIR/clusters/clusters 2>&1
  ${KUBECTL_CMD} get clusters.management.cattle.io -A -o yaml > $TMPDIR/clusters/clusters.yaml 2>&1

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

watch-logs() {

  techo "Live tailing debug logs from Rancher pods"
  techo "Please use Ctrl+C to finish tailing"
  mkdir -p $TMPDIR/rancher-logs/
  ${KUBECTL_CMD} -n cattle-system logs -f -l app=rancher -c rancher | tee $TMPDIR/rancher-logs/live-logs

}


pause() {

 read -n1 -rsp $'Press any key once finished logging with debug loglevel, or Ctrl+C to exit and leave debug loglevel enabled... \n'

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
enable-debug
if [ ! -z "${WATCH}" ]
then
  watch-logs
else
  techo "Debug loglevel has been set"
  pause
fi
disable-debug
cluster-info
archive
cleanup
