#!/bin/bash
# Which app to profile? Supported choices: rancher, cattle-cluster-agent, fleet-controller, fleet-agent
APP=rancher

# Which profiles to collect? Supported choices: goroutine, heap, threadcreate, block, mutex, profile
# Default profiles
DEFAULT_PROFILES=("goroutine" "heap" "profile")

# Assign default values to PROFILES if not provided by user
PROFILES=("${DEFAULT_PROFILES[@]}")

# How many seconds to wait between captures?
SLEEP=120

# Prefix for profile tarball name
PREFIX="rancher"

# Profile collection time (only required for CPU profiles)
DURATION=30

# Support tarball file (profiles will be added here)
MAIN_FILENAME="profiles-$(date +'%Y-%m-%d_%H_%M').tar"

# Optional Azure storage container SAS URL and token for uploading. Only creation permission is necessary.
BLOB_URL=
BLOB_TOKEN=

cleanup() {
  # APP=rancher only: set logging back to normal
  if [ "$APP" == "rancher" ]; then
    set_rancher_log_level info
  fi
  exit 0
}

trap cleanup SIGINT

export TZ=UTC

help() {
  echo "Rancher 2.x profile-collector
  Usage: profile-collector.sh [-a rancher -p goroutine,heap ]

  All flags are optional

  -a    Application: rancher, cattle-cluster-agent, fleet-controller, or fleet-agent
  -p    Profiles to be collected (comma separated): goroutine,heap,threadcreate,block,mutex,profile
  -s    Sleep time between loops in seconds
  -t    Time of CPU profile collections
  -h    This help"

}

techo() {
  echo "$(date "+%Y-%m-%d %H:%M:%S"): $*"

}

collect() {

  case $APP in
  rancher)
    CONTAINER=rancher
    NAMESPACE=cattle-system
    set_rancher_log_level debug
    ;;
  cattle-cluster-agent)
    CONTAINER=cluster-register
    NAMESPACE=cattle-system
    ;;
  fleet-controller)
    CONTAINER=fleet-controller
    NAMESPACE=cattle-fleet-system
    ;;
  fleet-agent)
    CONTAINER=fleet-agent
    if kubectl get namespace cattle-fleet-local-system >/dev/null; then
      NAMESPACE=cattle-fleet-local-system
    else
      NAMESPACE=cattle-fleet-system
    fi
    ;;
  esac

  while true; do

    TMPDIR=$(mktemp -d $MKTEMP_BASEDIR) || {
      techo 'Creating temporary directory failed, please check options'
      exit 1
    }
    techo "Created ${TMPDIR}"
    echo

    echo "Start: $(date -Iseconds)" >>${TMPDIR}/timestamps.txt

    kubectl top pods -A >>${TMPDIR}/top-pods.txt
    kubectl top nodes >>${TMPDIR}/top-nodes.txt

    for pod in $(kubectl -n $NAMESPACE get pods -l app=${APP} --no-headers -o custom-columns=name:.metadata.name); do
      for profile in ${PROFILES[@]}; do
        techo Getting $profile profile for $pod
        if [ "$profile" == "profile" ]; then
          kubectl exec -n $NAMESPACE $pod -c ${CONTAINER} -- curl -s http://localhost:6060/debug/pprof/${profile}?seconds=${DURATION} >${TMPDIR}/${pod}-${profile}-$(date +'%Y-%m-%dT%H_%M_%S')
        else
          kubectl exec -n $NAMESPACE $pod -c ${CONTAINER} -- curl -s http://localhost:6060/debug/pprof/${profile} >${TMPDIR}/${pod}-${profile}-$(date +'%Y-%m-%dT%H_%M_%S')
        fi
      done

      techo Getting logs for $pod
      kubectl logs --since 5m -n $NAMESPACE $pod -c ${CONTAINER} >${TMPDIR}/${pod}.log
      echo

      techo Getting previous logs for $pod
      kubectl logs -n $NAMESPACE $pod -c ${CONTAINER} --previous=true >${TMPDIR}/${pod}-previous.log
      echo

      if [ "$APP" == "rancher" ]; then
        techo Getting rancher-audit-logs for $pod
        kubectl logs --since 5m -n $NAMESPACE $pod -c rancher-audit-log >${TMPDIR}/${pod}-audit.log
        echo

        techo Getting metrics for Rancher
        kubectl exec -n $NAMESPACE $pod -c ${CONTAINER} -- bash -c 'curl -s -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k https://127.0.0.1/metrics' >${TMPDIR}/$pod-metrics.txt
        echo
      fi

      techo Getting rancher-event-logs for $pod
      kubectl get event --namespace $NAMESPACE --field-selector involvedObject.name=${pod} >${TMPDIR}/${pod}-events.txt
      echo

      techo Getting describe for $pod
      kubectl describe pod $pod -n $NAMESPACE >${TMPDIR}/${pod}-describe.txt
      echo
    done

    techo "Getting leases"
    kubectl get leases -n kube-system >${TMPDIR}/leases.txt

    techo "Getting pod details"
    kubectl get pods -A -o wide >${TMPDIR}/pods-wide.txt

    echo "End:   $(date -Iseconds)" >>${TMPDIR}/timestamps.txt

    FILENAME="${PREFIX}-profiles-$(date +'%Y-%m-%d_%H_%M').tar.xz"
    techo "Creating tarball ${FILENAME}"
    tar cfJ /tmp/${FILENAME} --directory ${TMPDIR}/ .

    # Upload to Azure Blob Storage if URL was set
    if [ -n "$BLOB_URL" ]; then
      techo "Uploading ${FILENAME}"
      curl -H "x-ms-blob-type: BlockBlob" --upload-file /tmp/${FILENAME} "${BLOB_URL}/${FILENAME}?${BLOB_TOKEN}"
    else
      tar rf "$MAIN_FILENAME" /tmp/${FILENAME}
    fi

    echo
    techo "Removing ${TMPDIR}"
    rm -r -f "${TMPDIR}" >/dev/null 2>&1

    techo "Sleeping ${SLEEP} seconds before next capture..."
    sleep ${SLEEP}
  done

}

while getopts "a:p:d:s:t:h" opt; do
  case $opt in
  a)
    APP="${OPTARG}"
    if [ "${APP}" != "rancher" ] && [ "${APP}" != "cattle-cluster-agent" ] && [ "${APP}" != "fleet-controller" ] && [ "${APP}" != "fleet-agent" ]; then
      help
    fi
    ;;
  p)
    IFS=',' read -r -a PROFILES <<<"${OPTARG}"

    # Check if the array is populated correctly (for debugging)
    techo "Profiles array: ${PROFILES[@]}"
    ;;
  s)
    SLEEP="${OPTARG}"
    ;;
  t)
    DURATION="${OPTARG}"
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
    ;;
  esac
done

set_rancher_log_level() {
  kubectl --namespace cattle-system get pods -l app=rancher --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do
    techo Setting $rancherpod $1 logging
    kubectl --namespace cattle-system exec $rancherpod -c rancher -- loglevel --set $1
  done

}

collect
