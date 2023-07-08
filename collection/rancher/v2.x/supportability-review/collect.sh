#!/bin/bash

if [ "${DEBUG}" == "true" ]; then
  set -x
fi

HELP_MENU() {
echo "Supportability Review
Usage: collect.sh [ -h ]

All flags are optional

-h      Print help menu for Supportability Review

Environment variables:

  RANCHER_URL: Specify Rancher Server URL (Ex: https://rancher.example.com)
  RANCHER_TOKEN: Specify Rancher Token to connect to Rancher Server
  SR_IMAGE: Use this variable to point to custom container image of Supportability Review

"
}

SR_IMAGE=${SR_IMAGE:-"ghcr.io/rancherlabs/supportability-review:latest"}

if [[ "$SR_IMAGE" != *":dev" ]]; then
  echo "pulling image: ${SR_IMAGE}"
  docker pull "${SR_IMAGE}"
fi

if [ ! `command -v docker` && `command -v nerdctl` && `command -v crictl` ]; then

  if [ "${CONTAINERD_ADDRESS}" == "" ]; then
    echo "error: CONTAINERD_ADDRESS is not set"
    exit 1
  fi
  CONTAINER_RUNTIME=nerdctl
else
  CONTAINER_RUNTIME=docker
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

  if [ "$1" == "-h" ]; then
    HELP_MENU
  fi

  $CONTAINER_RUNTIME run --rm \
  -it \
  --network host \
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

  $CONTAINER_RUNTIME run --rm \
    -it \
    --network host \
    -v `pwd`:/data \
    -v ${KUBECONFIG}:/tmp/kubeconfig.yml \
    "${SR_IMAGE}" \
    collect_info_from_rancher_setup.py --kubeconfig /tmp/kubeconfig.yml "$@"
fi
