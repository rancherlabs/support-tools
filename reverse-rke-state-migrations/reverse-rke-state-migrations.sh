#!/bin/bash

set -e
set -o pipefail

# Use this to specify a custom kubectl base command or options.
KUBECTL="kubectl"

# Use this to specify a custom curl base command or options.
# By default, we pass options that make curl silent, except when errors occur,
# and we also force CURL to error if HTTP requests do not receive successful
# (2xx) response codes.
CURL="curl -sSf"

function display_help() {
  echo 'This script can be used to reverse RKE cluster state migrations.'
  echo 'Please ensure the $RANCHER_TOKEN environment variable is set to a valid Rancher API admin token'
  echo 'Please also ensure the following tools are installed:'
  echo '  kubectl: https://kubernetes.io/docs/tasks/tools/#kubectl'
  echo '  jq:      https://jqlang.github.io/jq'
  echo '  yq:      https://mikefarah.gitbook.io/yq/#install'
  echo
  echo
  echo "Usage: $(basename $0) --rancher-host [Rancher hostname]"
  echo
  echo '  $RANCHER_TOKEN                  [Required]    Environment variable containing Rancher admin token'
  echo '  -n, --rancher-host              [Required]    Rancher hostname'
  echo '  -k, --insecure-skip-tls-verify  [Optional]    Skip certificate verification'
  echo "  -d, --debug                     [Optional]    Calls 'set -x'"
  echo "  -h, --help                                    Print this message"
}

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--rancher-host)
      RANCHER_HOST="$2"
      shift # past argument
      shift # past value
      ;;
    -k|--insecure-skip-tls-verify)
      KUBECTL="$KUBECTL --insecure-skip-tls-verify"
      CURL="$CURL -k"
      shift # past argument
      ;;
    -d|--debug)
      set -x
      shift # past argument
      ;;
    -h|--help)
      display_help
      exit 1
      ;;
    -*|--*)
      echo "Unknown option $1"
      display_help
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

# Make sure a Rancher API token was set
if [[ -z "$RANCHER_TOKEN" ]]; then
  echo 'ERROR: $RANCHER_TOKEN is unset'
  display_help
  exit 1
fi

# Make sure a rancher host was set
if [[ -z "$RANCHER_HOST" ]]; then
  echo 'ERROR: --rancher-host is unset'
  display_help
  exit 1
fi

# Make sure the jq command is available
if ! command -v "jq" &> /dev/null; then
  echo "Missing jq command. See download/installation instructions at https://jqlang.github.io/jq/."
  exit 1
fi

# Make sure the yq command is available
if ! command -v "yq" &> /dev/null; then
  echo "Missing yq command. See download/installation instructions at https://mikefarah.gitbook.io/yq/#install."
  exit 1
fi

# Make sure the kubectl command is available
if ! command -v "kubectl" &> /dev/null; then
  echo "Missing kubectl command. See download/installation instructions at https://kubernetes.io/docs/tasks/tools/#kubectl."
  exit 1
fi

# Downloads kubeconfig for the cluster with ID $MANAGEMENT_CLUSTER_ID.
downloadKubeConfig() {
  $CURL -X 'POST' -H 'accept: application/yaml' -u "$RANCHER_TOKEN" \
   "https://${RANCHER_HOST}/v3/clusters/${MANAGEMENT_CLUSTER_ID}?action=generateKubeconfig" \
   | yq -r '.config' > .kube/config-"$MANAGEMENT_CLUSTER_ID"
}

# Downloads kubeconfig for the local cluster.
getLocalKubeConfig() {
  $CURL -X 'POST' -H 'accept: application/yaml' -u "$RANCHER_TOKEN" \
   "https://${RANCHER_HOST}/v3/clusters/local?action=generateKubeconfig" \
    | yq -r '.config' > .kube/config
}

# Moves downstream cluster state from a secret to a configmap.
reverseMigrateClusterState() {
  # Load cluster state from the secret
  SECRET=$($KUBECTL get secret full-cluster-state -n kube-system -o yaml)
  if [ $? -ne 0 ]; then
    echo "[cluster=$MANAGEMENT_CLUSTER_ID] failed to fetch secret full-cluster-state, skipping this cluster"
    return
  fi

  # Make sure the cluster state is not empty or invalid
  CLUSTER_STATE=$(echo "$SECRET" | yq -r '.data.full-cluster-state' | base64 --decode)
  if [[ "$?" -ne 0 || "${PIPESTATUS[0]}" -ne 0 || "${PIPESTATUS[1]}" -ne 0 || "${PIPESTATUS[2]}" -ne 0 ]]; then
    echo "[cluster=$MANAGEMENT_CLUSTER_ID] failed to decode cluster state, skipping this cluster"
    return
  fi

  if [ -z "$CLUSTER_STATE" ]; then
    echo "[cluster=$MANAGEMENT_CLUSTER_ID] cluster state is empty, skipping this cluster"
    return
  fi

  # Copy cluster state to a configmap
  $KUBECTL create configmap full-cluster-state -n kube-system --from-literal=full-cluster-state="$CLUSTER_STATE"

  # Remove the secret
  $KUBECTL delete secret full-cluster-state -n kube-system
}

# Performs reverse migrations on all downstream RKE clusters.
reverseMigrateRKEClusters() {
  # Download kubeconfig for the local cluster
  getLocalKubeConfig

  # Fetch all RKE cluster IDs
  MANAGEMENT_CLUSTER_IDS=($(
    $CURL -H 'accept: application/json' -u "$RANCHER_TOKEN" \
    "https://${RANCHER_HOST}/v1/management.cattle.io.cluster?exclude=metadata.managedFields" \
    | jq -r '.data[] | select(.spec.rancherKubernetesEngineConfig) | .id')
  )

  # Migrate each RKE cluster's state
  for MANAGEMENT_CLUSTER_ID in "${MANAGEMENT_CLUSTER_IDS[@]}"
  do
    # Download and point to downstream cluster kubeconfig
    downloadKubeConfig
    export KUBECONFIG=".kube/config-$MANAGEMENT_CLUSTER_ID"

    echo "Moving state back to configmap for cluster $MANAGEMENT_CLUSTER_ID"
    set +e
    reverseMigrateClusterState
    set -e
  done

  # Remove the migration configmap since we've reversed the migrations
  if $KUBECTL get configmap migraterkeclusterstate -n cattle-system > /dev/null 2>&1; then
    echo "Deleting configmap migraterkeclusterstate"
    $KUBECTL delete configmap migraterkeclusterstate -n cattle-system
  fi
}

main() {
  # Create temp directory to which we'll download cluster kubeconfig files.
  cd "$(mktemp -d)"
  echo "Using temp directory $(pwd)"

  echo "WARNING: 'full-cluster-state' secrets will be deleted for downstream RKE clusters after being moved."
  echo -n "Please make sure you've backed them up before proceeding. Proceed? (yes/no) "
  read ANSWER

  if [ "$ANSWER" = "yes" ]; then
    mkdir -p .kube
    reverseMigrateRKEClusters
    rm -rf .kube
  elif [ "$ANSWER" = "no" ]; then
    echo "Aborting"
    exit 1
  else
    echo "Invalid response. Please type 'yes' or 'no'."
    exit 1
  fi
}

main
