#!/bin/bash

if [ "${DEBUG}" == "true" ]; then
  set -x
fi

# Using the same env var format used by dapper
REGISTRY=${REGISTRY:-"ghcr.io"}
REPO=${REPO:-"rancherlabs"}
APP=${APP:-"supportability-review"}
TAG=${TAG:-"latest"}
IMAGE="${REGISTRY}/${REPO}/${APP}:${TAG}"

if [ "$TAG" != "dev" ]; then
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
    -e REGISTRY="${REGISTRY}" \
    -e REPO="${REPO}" \
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
    -e REPO="${REPO}" \
    -e TAG="${TAG}" \
    -v ${KUBECONFIG}:/tmp/kubeconfig.yml \
     "${IMAGE}" \
    collect_info_from_rancher_setup.py --kubeconfig /tmp/kubeconfig.yml "$@"
fi
