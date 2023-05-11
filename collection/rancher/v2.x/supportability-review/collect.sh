#!/bin/bash

if [ "${DEBUG}" == "true" ]; then
  set -x
fi

SR_IMAGE=${SR_IMAGE:-"ghcr.io/rancherlabs/supportability-review:latest"}

if [[ "$SR_IMAGE" != *":dev" ]]; then
  echo "pulling image: ${IMAGE}"
  docker pull "${IMAGE}"
fi

if [ "${KUBECONFIG}" == "" ]; then
  if [ "${RANCHER_URL}" == "" ]; then
    echo "error: RANCHER_URL is not set"
    exit 1
  fi

  if [ "${RANCHER_TOKEN}" == "" ]; then
    echo "error: RANCHER_TOKEN is not set"
    exit 1
  fi

  docker run --rm \
    -it \
    -v `pwd`:/data \
    -e RANCHER_URL="${RANCHER_URL}" \
    -e RANCHER_TOKEN="${RANCHER_TOKEN}" \
    -e RANCHER_VERIFY_SSL_CERTS="${RANCHER_VERIFY_SSL_CERTS}" \
     "${SR_IMAGE}" \
    collect_info_from_rancher_setup.py "$@"
else
  # TODO: Check if it's absolute path
  # TODO: Check if the file exists and it's readable
  echo "KUBECONFIG specified: ${KUBECONFIG}"

  if [ ! -f "${KUBECONFIG}" ]; then
    echo "error: KUBECONFIG=${KUBECONFIG} specified, but cannot access that file"
    exit 1
  fi

  docker run --rm \
    -it \
    -v `pwd`:/data \
    -v ${KUBECONFIG}:/tmp/kubeconfig.yml \
     "${SR_IMAGE}" \
    collect_info_from_rancher_setup.py --kubeconfig /tmp/kubeconfig.yml "$@"
fi
