#!/bin/bash

if [ "${DEBUG}" == "true" ]; then
  set -x
fi

REGISTRY=${REGISTRY:-"ghcr.io/rancherlabs"}
REPO=${REPO:-"supportability-review"}
TAG=${TAG:-"latest"}
IMAGE="${REGISTRY}/${REPO}:${TAG}"

if [ "${KUBECONFIG}" == "" ]; then
  if [ "${RANCHER_URL}" == "" ]; then
    echo "error: RANCHER_URL is not set"
    exit 1
  fi

  if [ "${RANCHER_TOKEN}" == "" ]; then
    echo "error: RANCHER_TOKEN is not set"
    exit 1
  fi

  docker pull "${IMAGE}"
  docker run --rm \
    -it \
    -v `pwd`:/data \
    -e RANCHER_URL="${RANCHER_URL}" \
    -e RANCHER_TOKEN="${RANCHER_TOKEN}" \
    -e RANCHER_VERIFY_SSL_CERTS="${RANCHER_VERIFY_SSL_CERTS}" \
    -e REGISTRY="${REGISTRY}" \
    -e TAG="${TAG}" \
     "${IMAGE}" \
    collect_info_from_rancher_setup.py "$@"
else
  # TODO: Check if it's absolute path
  # TODO: Check if the file exists and it's readable
  echo "KUBECONFIG specified: ${KUBECONFIG}"
  docker run --rm \
    -it \
    -v `pwd`:/data \
    -e REGISTRY="${REGISTRY}" \
    -e TAG="${TAG}" \
    -v ${KUBECONFIG}:/tmp/kubeconfig.yml \
    "${REGISTRY}/${REPO}:${TAG}" \
    collect_info_from_rancher_setup.py --kubeconfig /tmp/kubeconfig.yml "$@"
fi
