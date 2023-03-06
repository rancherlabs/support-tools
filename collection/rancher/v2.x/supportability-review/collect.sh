#!/bin/bash

if [ "${DEBUG}" == "true" ]; then
  set -x
fi

REPO=${REPO:-"ghcr.io/rancherlabs"}
PROJECT=${PROJECT:-"supportability-scanner"}
TAG=${TAG:-"latest"}

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
    -e REPO="${REPO}" \
    -e TAG="${TAG}" \
    "${REPO}/${PROJECT}:${TAG}" \
    collect_info_from_rancher_setup.py "$@"
else
  # TODO: Check if it's absolute path
  # TODO: Check if the file exists and it's readable
  echo "KUBECONFIG specified: ${KUBECONFIG}"
  docker run --rm \
    -it \
    -v `pwd`:/data \
    -e REPO="${REPO}" \
    -e TAG="${TAG}" \
    -v ${KUBECONFIG}:/tmp/kubeconfig.yml \
    "${REPO}/${PROJECT}:${TAG}" \
    collect_info_from_rancher_setup.py --kubeconfig /tmp/kubeconfig.yml "$@"
fi
