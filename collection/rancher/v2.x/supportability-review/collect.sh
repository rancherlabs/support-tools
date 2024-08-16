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

SR_IMAGE=${SR_IMAGE:-"ghcr.io/rancher/supportability-review:latest"}

if [ "${CONTAINER_RUNTIME}" == "" ]; then
  if command -v docker &> /dev/null; then
    echo "setting CONTAINER_RUNTIME=docker"
    CONTAINER_RUNTIME="docker"
  elif command -v nerdctl &> /dev/null; then
    echo "setting CONTAINER_RUNTIME=nerdctl"
    CONTAINER_RUNTIME="nerdctl"
  elif command -v podman &> /dev/null; then
    echo "setting CONTAINER_RUNTIME=podman"
    CONTAINER_RUNTIME="podman"
  else
    echo "error: couldn't detect CONTAINER_RUNTIME"
    exit 1
  fi
else
  supported_runtime=false
  for runtime in docker nerdctl podman; do
    if [ "${CONTAINER_RUNTIME}" == ${runtime} ]; then
      supported_runtime=true
      break
    fi
  done
  if [ "${supported_runtime}" == false ]; then
    echo "error: unsupported CONTAINER_RUNTIME. Use docker|nerdctl|podman."
    exit 1
  fi
fi

if [[ "$SR_IMAGE" != *":dev" ]]; then
  echo "pulling image: ${SR_IMAGE}"
  $CONTAINER_RUNTIME pull "${SR_IMAGE}"
fi

CONTAINER_RUNTIME_ARGS=""
COLLECT_INFO_FROM_RANCHER_SETUP_ARGS=""

if [ "${SONOBUOY_TOLARATION_FILE}" != "" ]; then
  if [ ! -f "${SONOBUOY_TOLARATION_FILE}" ]; then
    echo "error: SONOBUOY_TOLARATION_FILE=${SONOBUOY_TOLARATION_FILE} specified, but cannot access that file"
    exit 1
  fi
  CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -v ${SONOBUOY_TOLARATION_FILE}:/tmp/sonobuoy_toleration.yml"
  COLLECT_INFO_FROM_RANCHER_SETUP_ARGS="$COLLECT_INFO_FROM_RANCHER_SETUP_ARGS --sonobuoy-toleration-file /tmp/sonobuoy_toleration.yml"
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

  CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -e RANCHER_URL="${RANCHER_URL}""
  CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -e RANCHER_TOKEN="${RANCHER_TOKEN}""
  CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -e RANCHER_VERIFY_SSL_CERTS="${RANCHER_VERIFY_SSL_CERTS}""
else
  # TODO: Check if it's absolute path
  # TODO: Check if the file exists and it's readable
  echo "KUBECONFIG specified: ${KUBECONFIG}"

  if [ ! -f "${KUBECONFIG}" ]; then
    echo "error: KUBECONFIG=${KUBECONFIG} specified, but cannot access that file"
    exit 1
  fi

  CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -v ${KUBECONFIG}:/tmp/kubeconfig.yml"
  COLLECT_INFO_FROM_RANCHER_SETUP_ARGS="$COLLECT_INFO_FROM_RANCHER_SETUP_ARGS --kubeconfig /tmp/kubeconfig.yml"
fi

CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -e S3_ENDPOINT_URL="${S3_ENDPOINT_URL}""
CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -e S3_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}""
CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -e S3_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}""
CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -e S3_REGION_NAME="${S3_REGION_NAME}""
CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -e S3_SSL_VERIFY="${S3_SSL_VERIFY}""
CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -e S3_BUCKET_NAME="${S3_BUCKET_NAME}""
CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS -e S3_FOLDER_NAME="${S3_FOLDER_NAME}""

CONTAINER_RUNTIME_ARGS="$CONTAINER_RUNTIME_ARGS ${SR_IMAGE}"

$CONTAINER_RUNTIME run --rm \
  -it \
  --network host \
  -v `pwd`:/data \
  $CONTAINER_RUNTIME_ARGS \
  collect_info_from_rancher_setup.py $COLLECT_INFO_FROM_RANCHER_SETUP_ARGS "$@"
