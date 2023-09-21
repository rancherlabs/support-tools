#!/usr/bin/env bash
#
# This script runs once as a "Job" in the cluster. Used to run commands
# that collect info at a cluster level.
#

SONOBUOY_RESULTS_DIR=${SONOBUOY_RESULTS_DIR:-"/tmp/results"}
ERROR_LOG_FILE="${SONOBUOY_RESULTS_DIR}/error.log"
SONOBUOY_DONE_FIE="${SONOBUOY_RESULTS_DIR}/done"
HOST_FS_PREFIX="${HOST_FS_PREFIX:-"/host"}"

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
  date "+%Y-%m-%d %H:%M:%S" > date.log

  kubectl version -o json > kubectl-version.json
  kubectl get nodes -o json > nodes.json
  kubectl get namespaces -o json > namespaces.json
  kubectl -n default get services -o json > services-default.json
  kubectl get crds -o json > crds.json
  kubectl get ds -n cattle-system -o json > cattle-system-daemonsets.json
  # TODO: This call might take a lot of time in scale setups. We need to reconsider usage.
  kubectl get pods -A -o json > pods.json
  jq -cr '.items | length' pods.json > pod-count
  jq -cr '[([.items[].spec.containers | length] | add), ([.items[].spec.initContainers | length] | add)] | add' pods.json > container-count
  jq -cr '[[.items[].spec.nodeName] | group_by(.) | map({(.[0]): length}) | add | to_entries[] | select(.value > 110) | .key] | length' pods.json > count-of-nodes-with-more-than-110-pods
  kubectl get deploy -n cattle-fleet-system -o json > cattle-fleet-system-deploy.json
  kubectl get settings.management.cattle.io server-version -o json > server-version.json
  kubectl get clusters.management.cattle.io -o json > clusters.management.cattle.io.json

  kubectl cluster-info dump > cluster-info.dump.log
}

collect_rke_info() {
  mkdir -p "${OUTPUT_DIR}/rke"
  echo "rke: nothing to collect yet"

  kubectl -n kube-system get configmap full-cluster-state -o jsonpath='{.data.full-cluster-state}' | jq -cr '.currentState.rkeConfig.network.plugin' > ${OUTPUT_DIR}/rke/cni
  kubectl -n kube-system get configmap full-cluster-state -o jsonpath='{.data.full-cluster-state}' | jq -cr '.currentState.rkeConfig.kubernetesVersion' > ${OUTPUT_DIR}/rke/kubernetesVersion
  kubectl -n kube-system get configmap full-cluster-state -o jsonpath='{.data.full-cluster-state}' | jq -cr '.currentState.rkeConfig.services.etcd | del(.backupConfig.s3BackupConfig)' > ${OUTPUT_DIR}/rke/etcd.json
  kubectl -n kube-system get configmap full-cluster-state -o jsonpath='{.data.full-cluster-state}' | jq -cr '.currentState.rkeConfig.dns' > ${OUTPUT_DIR}/rke/dns.json
}

collect_rke2_info() {
  mkdir -p "${OUTPUT_DIR}/rke2"
  ls ${HOST_FS_PREFIX}/var/lib/rancher/rke2/ > ${OUTPUT_DIR}/rke2/var-lib-rancher-rke2-directory 2>&1

  #Get RKE2 Configuration file(s), redacting secrets
  if [ -f "${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml" ]; then
    cat ${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml | sed -E 's/("|\x27)?(agent-token|token|etcd-s3-access-key|etcd-s3-secret-key|datastore-endpoint)("|\x27)?:\s*("|\x27)?.*("|\x27)?/\1\2\3: <REDACTED>/' > ${OUTPUT_DIR}/rke2/config.yaml
  fi
  if [ -d "${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml.d" ]; then
    mkdir -p "${OUTPUT_DIR}/rke2/config.yaml.d"
    for yaml in ${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml.d/*.yaml; do
      cat ${yaml} | sed -E 's/("|\x27)?(agent-token|token|etcd-s3-access-key|etcd-s3-secret-key|datastore-endpoint)("|\x27)?:\s*("|\x27)?.*("|\x27)?/\1\2\3: <REDACTED>/' > ${OUTPUT_DIR}/rke2/config.yaml.d/$(basename ${yaml})
    done
  fi
}


collect_k3s_info() {
  mkdir -p "${OUTPUT_DIR}/k3s"
  ls ${HOST_FS_PREFIX}/var/lib/rancher/k3s/ > ${OUTPUT_DIR}/k3s/var-lib-rancher-k3s-directory 2>&1

  #Get k3s Configuration file(s), redacting secrets
  if [ -f "${HOST_FS_PREFIX}/etc/rancher/k3s/config.yaml" ]; then
    cat ${HOST_FS_PREFIX}/etc/rancher/k3s/config.yaml | sed -E 's/("|\x27)?(agent-token|token|etcd-s3-access-key|etcd-s3-secret-key|datastore-endpoint)("|\x27)?:\s*("|\x27)?.*("|\x27)?/\1\2\3: <REDACTED>/' > ${OUTPUT_DIR}/k3s/config.yaml
  fi
  if [ -d "${HOST_FS_PREFIX}/etc/rancher/k3s/config.yaml.d" ]; then
    mkdir -p "${OUTPUT_DIR}/k3s/config.yaml.d"
    for yaml in ${HOST_FS_PREFIX}/etc/rancher/k3s/config.yaml.d/*.yaml; do
      cat ${yaml} | sed -E 's/("|\x27)?(agent-token|token|etcd-s3-access-key|etcd-s3-secret-key|datastore-endpoint)("|\x27)?:\s*("|\x27)?.*("|\x27)?/\1\2\3: <REDACTED>/' > ${OUTPUT_DIR}/k3s/config.yaml.d/$(basename ${yaml})
    done
  fi
}

collect_upstream_cluster_info() {
  kubectl get features.management.cattle.io -o json > features-management.json
  kubectl get bundledeployments.fleet.cattle.io -A -o json > bundledeployment.json
  kubectl get deploy -n cattle-system -o json > cattle-system-deploy.json
  kubectl get configmap -n kube-system cattle-controllers -o json > cattle-controllers-configmap.json
  kubectl get bundles.fleet.cattle.io -n fleet-local  -o json > fleet-local-bundle.json
  kubectl get apps.catalog.cattle.io -n cattle-logging-system -o json > cattle-logging-system-apps.json
  kubectl get apps.catalog.cattle.io -n cattle-monitoring-system -o json > cattle-monitoring-system-apps.json
  kubectl get apps.catalog.cattle.io -n cattle-resources-system -o json > cattle-resources-system-apps.json
  kubectl get backup.resources.cattle.io -o json > backup.json
  jq '[.items[] | select(.metadata.namespace == "cattle-system" and .metadata.labels.app == "rancher") | .spec.nodeName] | unique | length' pods.json > unique-rancher-pod-count-by-node

  kubectl get settings.management.cattle.io server-version -o json > server-version.json
  kubectl get settings.management.cattle.io install-uuid -o json > install-uuid.json
  kubectl get nodes.management.cattle.io -A -o json > nodes-cattle.json
  kubectl get --no-headers tokens.management.cattle.io | wc -l > token-count.txt
}

collect_app_info() {
  mkdir -p "${OUTPUT_DIR}/apps"

  kubectl get ds -n longhorn-system -o json > apps/longhorn-system-daemonsets.json
  NUM_OF_LONGHORN_DS=`jq -cr '.items | length' apps/longhorn-system-daemonsets.json`
  if [ $NUM_OF_LONGHORN_DS -eq 0 ]; then
    rm apps/longhorn-system-daemonsets.json
  fi

  kubectl get volumes.longhorn.io -n longhorn-system -o json > apps/longhorn-system-volumes.json
  if [ ! -s apps/longhorn-system-volumes.json ]; then
    rm apps/longhorn-system-volumes.json
  fi
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

  collect_app_info
}

delete_sensitive_info() {
  rm pods.json
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
