#!/bin/bash

# Which app to profile? Supported choices: rancher, cattle-cluster-agent
APP=cattle-cluster-agent

# Which profiles to collect? Supported choices: goroutine, heap, threadcreate, block, mutex, profile
PROFILES="goroutine heap"

# How many seconds to wait between captures?
SLEEP=120

# Prefix for profile tarball name
PREFIX="agent"

# Optional Azure storage container SAS URL and token for uploading. Only creation permission is necessary.
BLOB_URL=
BLOB_TOKEN=

cleanup() {
	# APP=rancher only: set logging back to normal
	kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do
		echo Setting $rancherpod back to normal logging
		kubectl -n cattle-system exec $rancherpod -c rancher -- loglevel --set error
	done
	exit 0
}

trap cleanup SIGINT

export TZ=UTC

while true; do
	# APP=rancher only: set logging to debug level
	kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do
		echo Setting $rancherpod debug logging
		kubectl -n cattle-system exec $rancherpod -c rancher -- loglevel --set debug
	done

	TMPDIR=$(mktemp -d $MKTEMP_BASEDIR) || {
		echo 'Creating temporary directory failed, please check options'
		exit 1
	}
	echo "Created ${TMPDIR}"
	echo

	echo "Start: $(date -Iseconds)" >>${TMPDIR}/timestamps.txt

	kubectl top pods -A >>${TMPDIR}/toppods.log
	kubectl top nodes >>${TMPDIR}/topnodes.log

	CONTAINER=rancher
	if [ "$APP" == "cattle-cluster-agent" ]; then
		CONTAINER=cluster-register
	fi

	for pod in $(kubectl -n cattle-system get pods -l app=${APP} --no-headers -o custom-columns=name:.metadata.name); do
		for profile in ${PROFILES}; do
			echo Getting $profile profile for $pod
			kubectl exec -n cattle-system $pod -c ${CONTAINER} -- curl -s http://localhost:6060/debug/pprof/${profile} -o ${profile}
			kubectl cp -n cattle-system -c ${CONTAINER} ${pod}:${profile} ${TMPDIR}/${pod}-${profile}-$(date +'%Y-%m-%dT%H_%M_%S')
		done

		echo Getting logs for $pod
		kubectl logs --since 5m -n cattle-system $pod -c ${CONTAINER} >${TMPDIR}/${pod}.log
		echo

		echo Getting previous logs for $pod
		kubectl logs -n cattle-system $pod -c ${CONTAINER} --previous=true >${TMPDIR}/${pod}-previous.log
		echo

		if [ "$APP" == "rancher" ]; then
			echo Getting rancher-audit-logs for $pod
			kubectl logs --since 5m -n cattle-system $pod -c rancher-audit-log >${TMPDIR}/${pod}-audit.log
			echo
		fi

		echo Getting rancher-event-logs for $pod
		kubectl get event --namespace cattle-system --field-selector involvedObject.name=${pod} >${TMPDIR}/${pod}-events.log		
		echo

		echo Getting describe for $pod
		kubectl describe pod $pod -n cattle-system >${TMPDIR}/${pod}-describe.log
		echo
	done

	echo "Getting pod details"
	kubectl get pods -A -o wide >${TMPDIR}/get_pods_A_wide.log

	echo "End:   $(date -Iseconds)" >>${TMPDIR}/timestamps.txt

	FILENAME="${PREFIX}-profiles-$(date +'%Y-%m-%d_%H_%M').tar.xz"
	echo "Creating tarball ${FILENAME}"
	tar cfJ /tmp/${FILENAME} --directory ${TMPDIR}/ .

	# Upload to Azure Blob Storage if URL was set
	if [ -n "$BLOB_URL" ]; then
		echo "Uploading ${FILENAME}"
		curl -H "x-ms-blob-type: BlockBlob" --upload-file /tmp/${FILENAME} "${BLOB_URL}/${FILENAME}?${BLOB_TOKEN}"
	fi

	echo
	echo "Removing ${TMPDIR}"
	rm -r -f "${TMPDIR}" >/dev/null 2>&1

	echo "Sleeping ${SLEEP} seconds before next capture..."
	sleep ${SLEEP}
done
