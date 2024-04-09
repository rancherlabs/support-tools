#!/bin/bash

# Azure storage container SAS URL and token for uploading. Only creation permission is necessary
BLOB_URL=''
BLOB_TOKEN=''

cleanup() {
	echo "Cleaning up..."
	echo "Setting rancher logs back to error"
	kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do kubectl -n cattle-system exec $rancherpod -c rancher -- loglevel --set error; done
	echo "Cleanup complete. Exiting."
	exit 0
}

trap cleanup SIGINT

echo Setting rancher debug logs
kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do kubectl -n cattle-system exec $rancherpod -c rancher -- loglevel --set debug; done

export TZ=UTC

while true; do
	TMPDIR=$(mktemp -d $MKTEMP_BASEDIR) || {
		echo 'Creating temporary directory failed, please check options'
		exit 1
	}
	echo "Created ${TMPDIR}"
	echo

	date -Iseconds >>${TMPDIR}/start_date

	kubectl top pods -A >>${TMPDIR}/toppods.log
	kubectl top nodes >>${TMPDIR}/topnodes.log

	for pod in $(kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=name:.metadata.name); do
		echo Getting heap for $pod
		kubectl exec -n cattle-system $pod -c rancher -- curl -s http://localhost:6060/debug/pprof/heap -o heap
		kubectl cp -n cattle-system -c rancher ${pod}:heap ${TMPDIR}/${pod}-heap-$(date +'%Y-%m-%dT%H_%M_%S')

		echo Getting goroutine for $pod
		kubectl exec -n cattle-system $pod -c rancher -- curl -s localhost:6060/debug/pprof/goroutine -o goroutine
		kubectl cp -n cattle-system -c rancher ${pod}:goroutine ${TMPDIR}/${pod}-goroutine-$(date +'%Y-%m-%dT%H_%M_%S')

		echo Getting profile for $pod
		kubectl exec -n cattle-system $pod -c rancher -- curl -s http://localhost:6060/debug/pprof/profile?seconds=30 -o profile
		kubectl cp -n cattle-system -c rancher ${pod}:profile ${TMPDIR}/${pod}-profile-$(date +'%Y-%m-%dT%H_%M_%S')

		echo Getting logs for $pod
		kubectl logs --since 5m -n cattle-system $pod -c rancher >${TMPDIR}/$pod.log
		echo
	done

	date -Iseconds >>${TMPDIR}/end_date

	FILENAME="profile-$(date +'%Y-%m-%d_%H_%M').tar.xz"
	echo "Creating tarball ${FILENAME}"
	tar cfJ /tmp/${FILENAME} --directory ${TMPDIR}/ .

	echo "Uploading ${FILENAME}"
	curl -H "x-ms-blob-type: BlockBlob" --upload-file /tmp/${FILENAME} "${BLOB_URL}/${FILENAME}?${BLOB_TOKEN}"

	echo
	echo "Removing ${TMPDIR}"
	rm -r -f "${TMPDIR}" >/dev/null 2>&1

	echo "Sleeping until the next capture..."
	# we want to at least one capture every 4 minutes
	# most time is spent in CPU profiling which takes 30s per rancher pod, and there is 3 of them = 90s
	# allow for another 30s for all other processing, that makes 2 minutes total
	# thus sleep for the remaining 2 minutes
	sleep 120
done
