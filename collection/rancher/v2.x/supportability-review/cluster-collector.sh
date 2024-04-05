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
  echo ${RANCHER_URL} > rancher_url 2>&1
  echo ${HOSTED_RANCHER_HOSTNAME_SUFFIX} > hosted_rancher_hostname_suffix 2>&1

  kubectl version -o json > kubectl-version.json
  kubectl get nodes -o json > nodes.json
  kubectl get namespaces -o json > namespaces.json
  kubectl -n default get services -o json > services-default.json
  kubectl get crds -o json > crds.json
  kubectl get ds -n cattle-system -o json > cattle-system-daemonsets.json
  kubectl get ds -n kube-system -o json > kube-system-daemonsets.json
  kubectl get ds -n calico-system -o json > calico-system-daemonsets.json
  # TODO: This call might take a lot of time in scale setups. We need to reconsider usage.
  kubectl get pods -A -o json > pods.json
  jq -cr '.items | length' pods.json > pod-count
  jq -cr '[([.items[].spec.containers | length] | add), ([.items[].spec.initContainers | length] | add)] | add' pods.json > container-count
  cat pods.json | jq -cr '
.items
| map(.spec.nodeName)
| group_by(.)
| map({name: .[0], count: length})
| {items: .}
' > pod-count-per-node.json
  jq -cr '.items[] | select(.metadata.deletionTimestamp) | .metadata.name' pods.json > terminating-pods
  jq -c '.items[]' pods.json | {
    while read -r item; do
      # Skip sonobuoy pods because they are in ContainerCreating state
      namespace=$(echo $item | tr '\n' ' ' | jq -cr '.metadata.namespace')
      if [ $namespace == $SONOBUOY_NAMESPACE ]; then
        continue
      fi

      name=$(echo $item | tr '\n' ' ' | jq -cr '.metadata.name')
      has_container_statuses=$(echo $item | tr '\n' ' ' | jq -cr '.status | has("containerStatuses")')
      if [ $has_container_statuses == "false" ]; then
        echo $name
        continue
      fi
      container_statuses=$(echo $item | tr '\n' ' ' | jq -cr '.status.containerStatuses')
      echo $container_statuses | jq -c '.[]' | {
        while read -r status; do
          # Check Running Pod
          has_running=$(echo $status | tr '\n' ' ' | jq -cr '.state | has("running")')
          if [ $has_running == "true" ]; then
            continue
          fi

          # Check Completed Job
          has_terminated=$(echo $status | tr '\n' ' ' | jq -cr '.state | has("terminated")')
          if [ $has_terminated == "true" ]; then
            reason_is_completed=$(echo $status | tr '\n' ' ' | jq -cr '.state.terminated.reason == "Completed"')
            if [ $reason_is_completed == "true" ]; then
              continue
            fi
          fi

          echo $name
        done
      }
    done
  } > invalid-pods
  jq -c '.items[]' nodes.json | {
    RESULT_JSON=""
    while read -r item; do
      NODENAME=$(echo $item | tr '\n' ' ' | jq -cr '.metadata.name')
      IP_LIST=$(jq ".items[] | select(.spec.nodeName == \"$NODENAME\") | .status.podIPs[].ip" pods.json | jq -s '.')
      ADDITONAL_JSON=$(echo "{\""$NODENAME"\":" $IP_LIST "}")
      RESULT_JSON=$(jq -s add <<< "$RESULT_JSON $ADDITONAL_JSON")
    done
    echo ${RESULT_JSON} | jq '.' > pod-ipaddresses.json
  }
  kubectl get services -A -o json > services.json
  jq -cr '.items[] | select(.metadata.deletionTimestamp) | .metadata.name' services.json > terminating-services
  kubectl get deploy -n cattle-system -o json | jq '.items[] | select(.metadata.name=="cattle-cluster-agent") | .status.conditions[] | select(.type=="Available") | .status == "True"' > cattle-cluster-agent-is-running
  kubectl get deploy -n cattle-fleet-system -o json > cattle-fleet-system-deploy.json
  kubectl get settings.management.cattle.io server-version -o json > server-version.json
  kubectl get clusters.management.cattle.io -o json > clusters.management.cattle.io.json
  kubectl get storageclasses.storage.k8s.io -A -o json > storageclasses.storage.k8s.io.json
  kubectl get persistentvolumeclaims -A -o json > persistentvolumeclaims.json
  kubectl get apps.catalog.cattle.io -n cattle-logging-system -o json > cattle-logging-system-apps.json
  kubectl get apps.catalog.cattle.io -n istio-system -o json > istio-system-apps.json
  kubectl get apps.catalog.cattle.io -n cis-operator-system -o json > cis-operator-system-apps.json
  kubectl get apps.catalog.cattle.io -n cattle-monitoring-system -o json > cattle-monitoring-system-apps.json
  if [ $(jq '.items | length' cattle-monitoring-system-apps.json) -lt 1 ]; then
    rm cattle-monitoring-system-apps.json
  fi

  # Make collection optional
  if [ ! -z "${SR_COLLECT_CLUSTER_INFO_DUMP}" ]; then
    echo "SR_COLLECT_CLUSTER_INFO_DUMP is set, hence collecting cluster-info dump"
    kubectl cluster-info dump > cluster-info.dump.log
  fi
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

  #Get RKE2 Configuration file(s), redacting secrets
  if [ -f "${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml" ]; then
    cat ${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml | sed -E 's/("|\x27)?(agent-token|token|etcd-s3-access-key|etcd-s3-secret-key|datastore-endpoint)("|\x27)?:\s*("|\x27)?.*("|\x27)?/\1\2\3: <REDACTED>/' > ${OUTPUT_DIR}/rke2/config.yaml
  else
    touch ${OUTPUT_DIR}/rke2/config.yaml
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

  #Get k3s Configuration file(s), redacting secrets
  if [ -f "${HOST_FS_PREFIX}/etc/rancher/k3s/config.yaml" ]; then
    cat ${HOST_FS_PREFIX}/etc/rancher/k3s/config.yaml | sed -E 's/("|\x27)?(agent-token|token|etcd-s3-access-key|etcd-s3-secret-key|datastore-endpoint)("|\x27)?:\s*("|\x27)?.*("|\x27)?/\1\2\3: <REDACTED>/' > ${OUTPUT_DIR}/k3s/config.yaml
  else
    touch ${OUTPUT_DIR}/k3s/config.yaml
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
  kubectl get apps.catalog.cattle.io -n cattle-resources-system -o json > cattle-resources-system-apps.json
  kubectl get backup.resources.cattle.io -o json > backup.json
  jq '[.items[] | select(.metadata.namespace == "cattle-system" and .metadata.labels.app == "rancher") | .spec.nodeName] | unique | length' pods.json > unique-rancher-pod-count-by-node
  number_of_rancher_pods=$(jq -cr '[.items[] | select(.metadata.namespace == "cattle-system" and .metadata.labels.app == "rancher") | .metadata.name] | length' pods.json)
  if [ $number_of_rancher_pods ]; then
    jq -cr '[.items[] | select(.metadata.namespace == "cattle-system" and .metadata.labels.app == "rancher")] | .[0] | .status.containerStatuses[0].imageID | split("@") | .[1] | split(":") | .[1]' pods.json > rancher-imageid.txt
  fi

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
  rm services.json
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
