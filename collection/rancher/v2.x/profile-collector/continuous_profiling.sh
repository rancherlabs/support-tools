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

# Log level, default debug
LOGLEVEL="debug"

# Profile collection time (only required for CPU profiles)
DURATION=30

# Support tarball file (profiles will be added here)
MAIN_FILENAME="profiles-$(date +'%Y-%m-%d_%H_%M').tar"

# Optional Azure storage container SAS URL and token for uploading. Only creation permission is necessary.
BLOB_URL=
BLOB_TOKEN=

techo() {
  echo "$(date "+%Y-%m-%d %H:%M:%S"): $*"
}

set_rancher_log_level() {
  local level="$1"

  kubectl --namespace cattle-system get pods -l app=rancher --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do
    techo Setting "$rancherpod" "$level" logging
    kubectl --namespace cattle-system exec "$rancherpod" -c rancher -- loglevel --set "$level"
  done
}

cleanup_app() {
  case "$APP" in
  rancher)
    # timing out to avoid cleanup to hang the whole terminal
    if command -v timeout >/dev/null; then
      timeout 5s set_rancher_log_level info || techo "Warning: Failed to set log level to info"
    else
      set_rancher_log_level info
    fi
    ;;
  fleet-controller | fleet-agent)
    if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
      kill "$PORT_FORWARD_PID" 2>/dev/null || true
    fi
    ;;
  esac
}

cleanup_files() {
  techo "Removing $TMPDIR"
  [[ -n "$TMPDIR" ]] && rm -rf "$TMPDIR"
  techo "Removing $FILENAME"
  [[ -n "$FILENAME" ]] && rm -f "/tmp/$FILENAME"
}

shutdown() {
  # disable trap to prevent infinite loops if a command fails
  trap - EXIT SIGINT SIGTERM

  techo "Shutting down safely..."
  cleanup_app

  # this ensures no process keeps running from collect_rancher_pod
  jobs -p | xargs -r kill 2>/dev/null || true

  cleanup_files

  exit 0
}

export TZ=UTC

help() {
  echo "Rancher 2.x profile-collector
  Usage: profile-collector.sh [-a rancher -p goroutine,heap ]

  All flags are optional

  -a    Application: rancher, cattle-cluster-agent, fleet-controller, or fleet-agent
  -p    Profiles to be collected (comma separated): goroutine,heap,threadcreate,block,mutex,profile
  -s    Sleep time between loops in seconds
  -t    Time of CPU profile collections
  -l    Log level of the Rancher pods: debug or trace
  -h    This help"

}

collect_pod() {
  local pod="$1"
  local namespace="$2"
  local container="$3"
  local tmpdir="$4"

  techo Getting logs for pod:"$pod"
  kubectl logs --since 5m -n "$namespace" "$pod" -c "$container" >"$tmpdir"/"$pod".log
  echo

  techo Getting previous logs for pod:"$pod"
  kubectl logs -n "$namespace" "$pod" -c "$container" --previous=true >"$tmpdir"/"$pod"-previous.log
  echo

  techo Getting events for pod:"$pod"
  kubectl get event --namespace "$namespace" --field-selector involvedObject.name="$pod" >"$tmpdir"/"$pod"-events.txt
  echo

  techo Getting describe for pod:"$pod"
  kubectl describe pod "$pod" -n "$namespace" >"$tmpdir"/"$pod"-describe.txt
  echo
}

collect_rancher_pod() {

  local pod="$1"

  for profile in ${PROFILES[@]}; do
    techo Getting $profile profile for $pod
    if [ "$profile" == "profile" ]; then
      kubectl exec -n $NAMESPACE $pod -c ${CONTAINER} -- curl -s http://localhost:6060/debug/pprof/${profile}?seconds=${DURATION} >${TMPDIR}/${pod}-${profile}-$(date +'%Y-%m-%dT%H_%M_%S')
    else
      kubectl exec -n $NAMESPACE $pod -c ${CONTAINER} -- curl -s http://localhost:6060/debug/pprof/${profile} >${TMPDIR}/${pod}-${profile}-$(date +'%Y-%m-%dT%H_%M_%S')
    fi
  done

  collect_pod "$pod" "$NAMESPACE" "$CONTAINER" "$TMPDIR"

  if [ "$APP" == "rancher" ]; then
    techo Getting rancher-audit-logs for $pod
    kubectl logs --since 5m -n $NAMESPACE $pod -c rancher-audit-log >${TMPDIR}/${pod}-audit.log
    echo

    techo Getting metrics for Rancher
    kubectl exec -n $NAMESPACE $pod -c ${CONTAINER} -- bash -c 'curl -s -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k https://127.0.0.1/metrics' >${TMPDIR}/$pod-metrics.txt
    echo
  fi
}

collect_rancher() {

  for pod in $(kubectl -n $NAMESPACE get pods -l app=${APP} --no-headers -o custom-columns=name:.metadata.name); do
    collect_rancher_pod "$pod" &
  done

  wait
}

collect_fleet() {

  pod=$(kubectl -n $NAMESPACE get pods -l app=${APP} --no-headers -o custom-columns=name:.metadata.name)

  for profile in ${PROFILES[@]}; do
    techo Getting $profile profile for $pod
    if [ "$profile" == "profile" ]; then
      curl -s http://localhost:60601/debug/pprof/${profile}?seconds=${DURATION} >${TMPDIR}/${pod}-${profile}-$(date +'%Y-%m-%dT%H_%M_%S')
    else
      curl -s http://localhost:60601/debug/pprof/${profile} >${TMPDIR}/${pod}-${profile}-$(date +'%Y-%m-%dT%H_%M_%S')
    fi
  done

  collect_pod "$pod" "$NAMESPACE" "$CONTAINER" "$TMPDIR"
}

init_app_env() {
  case "$APP" in
  rancher)
    CONTAINER=rancher
    NAMESPACE=cattle-system
    set_rancher_log_level "$LOGLEVEL"
    ;;
  cattle-cluster-agent)
    CONTAINER=cluster-register
    NAMESPACE=cattle-system
    ;;
  fleet-controller)
    CONTAINER=fleet-controller
    NAMESPACE=cattle-fleet-system
    pod=$(kubectl -n "$NAMESPACE" get pods -l app="$APP" --no-headers -o custom-columns=name:.metadata.name)
    kubectl port-forward -n "$NAMESPACE" "$pod" 60601:6060 &
    PORT_FORWARD_PID="$!"
    ;;
  fleet-agent)
    CONTAINER=fleet-agent
    if kubectl get namespace cattle-fleet-local-system >/dev/null; then
      NAMESPACE=cattle-fleet-local-system
      pod=$(kubectl -n "$NAMESPACE" get pods -l app="$APP" --no-headers -o custom-columns=name:.metadata.name)
      kubectl port-forward -n "$NAMESPACE" "$pod" 60601:6060 &
      PORT_FORWARD_PID="$!"
    else
      NAMESPACE=cattle-fleet-system
      pod=$(kubectl -n "$NAMESPACE" get pods -l app="$APP" --no-headers -o custom-columns=name:.metadata.name)
      kubectl port-forward -n "$NAMESPACE" "$pod" 60601:6060 &
      PORT_FORWARD_PID="$!"
    fi
    ;;
  esac
}

collect() {
  init_app_env

  trap shutdown EXIT SIGINT SIGTERM

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

    if [ "$APP" == "rancher" ] || [ "$APP" == "cattle-cluster-agent" ]; then
      collect_rancher
    else
      collect_fleet
    fi

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
    cleanup_files
    echo

    techo "Sleeping ${SLEEP} seconds before next capture..."
    sleep ${SLEEP}
  done

}

while getopts "a:p:d:s:t:l:h" opt; do
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
  l)
    LOGLEVEL="${OPTARG}"
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

collect
