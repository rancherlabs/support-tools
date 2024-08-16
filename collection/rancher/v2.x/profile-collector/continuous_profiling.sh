#!/bin/bash
# Which app to profile? Supported choices: rancher, cattle-cluster-agent
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
  kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do
    techo Setting $rancherpod back to normal logging
    kubectl -n cattle-system exec $rancherpod -c rancher -- loglevel --set error
  done
  exit 0
}

trap cleanup SIGINT

export TZ=UTC

help() {
  echo "Rancher 2.x profile-collector
  Usage: profile-collector.sh [-a rancher -p goroutine,heap ]

  All flags are optional

  -a    Application, either rancher or cattle-cluster-agent
  -p    Profiles to be collected (comma separated): goroutine,heap,threadcreate,block,mutex,profile
  -s    Sleep time between loops in seconds
  -t    Time of CPU profile collections
  -h    This help"

}

collect() {

  while true; do
    # APP=rancher only: set logging to debug level
    kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do
      techo Setting $rancherpod debug logging
      kubectl -n cattle-system exec $rancherpod -c rancher -- loglevel --set debug
    done

    TMPDIR=$(mktemp -d $MKTEMP_BASEDIR) || {
      techo 'Creating temporary directory failed, please check options'
      exit 1
    }
    techo "Created ${TMPDIR}"
    echo

    echo "Start: $(date -Iseconds)" >>${TMPDIR}/timestamps.txt

    kubectl top pods -A >>${TMPDIR}/top-pods.txt
    kubectl top nodes >>${TMPDIR}/top-nodes.txt

    CONTAINER=rancher
    if [ "$APP" == "cattle-cluster-agent" ]; then
      CONTAINER=cluster-register
    fi

    for pod in $(kubectl -n cattle-system get pods -l app=${APP} --no-headers -o custom-columns=name:.metadata.name); do
      for profile in ${PROFILES[@]}; do
        techo Getting $profile profile for $pod
        if [ "$profile" == "profile" ]; then
          kubectl exec -n cattle-system $pod -c ${CONTAINER} -- curl -s http://localhost:6060/debug/pprof/${profile}?seconds=${DURATION} -o ${profile}
        else
          kubectl exec -n cattle-system $pod -c ${CONTAINER} -- curl -s http://localhost:6060/debug/pprof/${profile} -o ${profile}
        fi
        kubectl cp -n cattle-system -c ${CONTAINER} ${pod}:${profile} ${TMPDIR}/${pod}-${profile}-$(date +'%Y-%m-%dT%H_%M_%S')
      done

      techo Getting logs for $pod
      kubectl logs --since 5m -n cattle-system $pod -c ${CONTAINER} >${TMPDIR}/${pod}.log
      echo

      techo Getting previous logs for $pod
      kubectl logs -n cattle-system $pod -c ${CONTAINER} --previous=true >${TMPDIR}/${pod}-previous.log
      echo

      if [ "$APP" == "rancher" ]; then
        techo Getting rancher-audit-logs for $pod
        kubectl logs --since 5m -n cattle-system $pod -c rancher-audit-log >${TMPDIR}/${pod}-audit.log
        echo
      fi

      techo Getting rancher-event-logs for $pod
      kubectl get event --namespace cattle-system --field-selector involvedObject.name=${pod} >${TMPDIR}/${pod}-events.txt
      echo

      techo Getting describe for $pod
      kubectl describe pod $pod -n cattle-system >${TMPDIR}/${pod}-describe.txt
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
    if [ "${APP}" != "rancher" ] && [ "${APP}" != "cattle-cluster-agent" ]; then
      help
    fi
    ;;
  p)
    IFS=',' read -r -a PROFILES <<<"${OPTARG}"

    # Check if the array is populated correctly (for debugging)
    techo "Profiles array: ${PROFILES[@]}"

    # Iterate over each profile in the array
    for profile in "${PROFILES[@]}"; do
      case $profile in
      goroutine | heap | threadcreate | block | mutex | profile)
        # Valid profile, do nothing
        ;;
      *)
        techo "Invalid profile: $profile"
        help && exit 0
        ;;
      esac
    done
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

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"

}

techo() {
  echo "$(timestamp): $*"

}

collect
