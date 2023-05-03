#!/usr/bin/env bash
#
# This script runs once as a "Job" in the cluster. Used to run commands
# that collect info at a cluster level.
#

CONFIG_DIR="${CONFIG_DIR:-/etc/kube-bench/cfg}"
SONOBUOY_RESULTS_DIR=${SONOBUOY_RESULTS_DIR:-"/tmp/results"}
ERROR_LOG_FILE="${SONOBUOY_RESULTS_DIR}/error.log"
SONOBUOY_DONE_FIE="${SONOBUOY_RESULTS_DIR}/done"

OUTPUT_DIR="${SONOBUOY_RESULTS_DIR}/output"
LOG_DIR="${OUTPUT_DIR}/logs"
TAR_OUTPUT_FILE="${SONOBUOY_RESULTS_DIR}/clusterinfo.tar.gz"

# This is set from outside, otherwise assuming rke
CLUSTER_PROVIDER=${CLUSTER_PROVIDER:-"rke"}

handle_error() {
  if [ "${DEBUG}" == "true" ]  || [ "${DEV}" == "true" ]; then
    sleep infinity
  fi
  echo -n "${ERROR_LOG_FILE}" > "${SONOBUOY_DONE_FIE}"
}

trap 'handle_error' ERR

set -x

prereqs() {
  mkdir -p "${OUTPUT_DIR}"
  mkdir -p "${LOG_DIR}"
}

collect_common_cluster_info() {
  kubectl get nodes -o json > nodes.json
  kubectl get namespaces -o json > namespaces.json
  kubectl -n default get services -o json > services-default.json
  kubectl get crds -o json > crds.json
  kubectl get configmap -n kube-system -o json > kube-system-configmap.json
  kubectl get ds -n cattle-system-daemonsets -o json > cattle-system-daemonsets.json
  # TODO: This call might take a lot of time in scale setups. We need to reconsider usage.
  kubectl get pods -A -o json > pods.json
  kubectl get deploy -n cattle-fleet-system -o json > cattle-fleet-system-deploy.json

  kubectl cluster-info dump > cluster-info.dump.log
}

collect_rke_info() {
  mkdir -p "${OUTPUT_DIR}/rke"
  echo "rke: nothing to collect yet"
}

collect_rke2_info() {
  mkdir -p "${OUTPUT_DIR}/rke2"
  echo "rke2: nothing to collect yet"
}

collect_k3s_info() {
  mkdir -p "${OUTPUT_DIR}/k3s"
  echo "k3s: nothing to collect yet"
}

collect_upstream_cluster_info() {
  kubectl get features.management.cattle.io -o json > features-management.json
  kubectl get bundledeployments.fleet.cattle.io -A -o json > bundledeployment.json
  kubectl get deploy -n cattle-system -o json > cattle-system-deploy.json
  kubectl get bundles.fleet.cattle.io -n fleet-local  -o json > fleet-local-bundle.json
  kubectl get clusters.management.cattle.io -o json > clusters.management.cattle.io.json
  kubectl get apps.catalog.cattle.io -n cattle-logging-system -o json > cattle-logging-system-apps.json
  kubectl get apps.catalog.cattle.io -n cattle-monitoring-system -o json > cattle-monitoring-system-apps.json
  kubectl get apps.catalog.cattle.io -n cattle-resources-system -o json > cattle-resources-system-apps.json
  kubectl get settings.management.cattle.io server-version -o json > server-version.json
  kubectl get backup.resources.cattle.io -o json > backup.json
}

collect_cluster_info() {
  collect_common_cluster_info
  if [ "${IS_UPSTREAM_CLUSTER}" == "true" ]; then
    collect_upstream_cluster_info
  fi

  case $CLUSTER_PROVIDER in
    "rke")
      collect_rke_info
    ;;
    "rke2")
      collect_rke2_info
    ;;
    "k3s")
      collect_k3s_info
    ;;
    *)
      echo "error: CLUSTER_PROVIDER is not set"
    ;;
  esac
}

delete_sensitive_info() {
  echo "nothing to delete yet"
}


main() {
  echo "start"
  date "+%Y-%m-%d %H:%M:%S"

  prereqs

  # Note:
  #       Don't prefix any of the output files. The following line needs to be
  #       adjusted accordingly.
  cd "${OUTPUT_DIR}"

  collect_cluster_info
  delete_sensitive_info

  if [ "${DEBUG}" != "true" ]; then
    tar czvf "${TAR_OUTPUT_FILE}" -C "${OUTPUT_DIR}" .
    echo -n "${TAR_OUTPUT_FILE}" > "${SONOBUOY_DONE_FIE}"
  else
    echo "Running in DEBUG mode, plugin will NOT exit [cleanup by deleting namespace]."
  fi

  echo "end"
  date "+%Y-%m-%d %H:%M:%S"

  # Wait
  sleep infinity
}

main
