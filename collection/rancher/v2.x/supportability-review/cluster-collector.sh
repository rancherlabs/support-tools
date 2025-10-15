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
  kubectl get deploy -n cattle-system -o json > cattle-system-deploy.json
  kubectl get deploy -n cattle-fleet-system -o json > cattle-fleet-system-deploy.json
  kubectl get deploy -n cattle-neuvector-system -o json > cattle-neuvector-system-deploy.json
  kubectl get statefulsets -n cattle-fleet-system -o json > cattle-fleet-system-statefulsets.json
  kubectl get settings.management.cattle.io server-version -o json > server-version.json
  if [ ! -s server-version.json ]; then
    rm server-version.json
  fi
  kubectl get clusters.management.cattle.io -o json > clusters.management.cattle.io.json
  if [ ! -s clusters.management.cattle.io.json ]; then
    rm clusters.management.cattle.io.json
  fi
  kubectl get storageclasses.storage.k8s.io -A -o json > storageclasses.storage.k8s.io.json
  kubectl get persistentvolumeclaims -A -o json > persistentvolumeclaims.json
  kubectl get apps.catalog.cattle.io -n cattle-logging-system -o json > cattle-logging-system-apps.json
  kubectl get apps.catalog.cattle.io -n istio-system -o json > istio-system-apps.json
  if [ ! -s istio-system-apps.json ]; then
    rm istio-system-apps.json
  fi
  kubectl get apps.catalog.cattle.io -n cattle-monitoring-system -o json > cattle-monitoring-system-apps.json
  if [ -s cattle-monitoring-system-apps.json ]; then
    if [ $(jq '.items | length' cattle-monitoring-system-apps.json) -lt 1 ]; then
      rm cattle-monitoring-system-apps.json
    fi
  else
    rm cattle-monitoring-system-apps.json
  fi

  # Collect API version info
  mkdir -p "${OUTPUT_DIR}/api_version"
  kubectl get CronJob -A -o json | jq '{"items": [.items[] | {"apiVersion": .apiVersion, "metadata": {"name": .metadata.name, "namespace": .metadata.namespace }}]}' > api_version/CronJob.json
  kubectl get CSIStorageCapacity -A -o json | jq '{"items": [.items[] | {"apiVersion": .apiVersion, "metadata": {"name": .metadata.name, "namespace": .metadata.namespace }}]}' > api_version/CSIStorageCapacity.json
  kubectl get EndpointSlice -A -o json | jq '{"items": [.items[] | {"apiVersion": .apiVersion, "metadata": {"name": .metadata.name, "namespace": .metadata.namespace }}]}' > api_version/EndpointSlice.json
  kubectl get Event -A -o json | jq '{"items": [.items[] | {"apiVersion": .apiVersion, "metadata": {"name": .metadata.name, "namespace": .metadata.namespace }}]}' > api_version/Event.json
  kubectl get FlowSchema -A -o json | jq '{"items": [.items[] | select(.metadata.annotations."apf.kubernetes.io/autoupdate-spec" == "false" or .metadata.generation != 1) | {"apiVersion": .apiVersion, "metadata": {"name": .metadata.name, "namespace": .metadata.namespace }}]}' > api_version/FlowSchema.json
  kubectl get HorizontalPodAutoscaler -A -o json | jq '{"items": [.items[] | {"apiVersion": .apiVersion, "metadata": {"name": .metadata.name, "namespace": .metadata.namespace }}]}' > api_version/HorizontalPodAutoscaler.json
  kubectl get PodDisruptionBudget -A -o json | jq '{"items": [.items[] | {"apiVersion": .apiVersion, "metadata": {"name": .metadata.name, "namespace": .metadata.namespace }}]}' > api_version/PodDisruptionBudget.json
  kubectl get PodSecurityPolicy -A -o json | jq '{"items": [.items[] | {"apiVersion": .apiVersion, "metadata": {"name": .metadata.name, "namespace": .metadata.namespace }}]}' > api_version/PodSecurityPolicy.json
  kubectl get RuntimeClass -A -o json | jq '{"items": [.items[] | {"apiVersion": .apiVersion, "metadata": {"name": .metadata.name, "namespace": .metadata.namespace }}]}' > api_version/RuntimeClass.json

  # Make collection optional
  if [ ! -z "${SR_COLLECT_CLUSTER_INFO_DUMP}" ]; then
    echo "SR_COLLECT_CLUSTER_INFO_DUMP is set, hence collecting cluster-info dump"
    kubectl cluster-info dump > cluster-info.dump.log
  fi

  # Run Trivy Vulnerability scan
  /etc/sonobuoy/trivy.py ${SONOBUOY_NAMESPACE} > trivy.log 2>&1

  # Check bitnami images
  jq -cr '.items[].spec.containers[].image' pods.json | grep "bitnami/" > bitnami-image
  jq -cr '.items[].spec.containers[].image' pods.json | grep "bitnamilegacy/" > bitnamilegacy-image
}

collect_rke_info() {
  mkdir -p "${OUTPUT_DIR}/rke"

  kubectl -n kube-system get secret | grep full-cluster-state
  if [ $? -eq 0 ]; then
    kubectl -n kube-system get secret full-cluster-state -o jsonpath='{.data.full-cluster-state}' | base64 -d > ${OUTPUT_DIR}/rke/full-cluster-state.json
    echo "true" > ${OUTPUT_DIR}/rke/CVE-2023-32191.txt
  else
    kubectl -n kube-system get configmap full-cluster-state -o jsonpath='{.data.full-cluster-state}' > ${OUTPUT_DIR}/rke/full-cluster-state.json
    echo "false" > ${OUTPUT_DIR}/rke/CVE-2023-32191.txt
  fi
  jq -cr '.currentState.rkeConfig.network.plugin' ${OUTPUT_DIR}/rke/full-cluster-state.json > ${OUTPUT_DIR}/rke/cni
  jq -cr '.currentState.rkeConfig.services.etcd | del(.backupConfig.s3BackupConfig)' ${OUTPUT_DIR}/rke/full-cluster-state.json > ${OUTPUT_DIR}/rke/etcd.json
  jq -cr '.currentState.rkeConfig.services.kubeApi' ${OUTPUT_DIR}/rke/full-cluster-state.json > ${OUTPUT_DIR}/rke/kubeApi.json
  jq -cr '.currentState.rkeConfig.services.kubeController' ${OUTPUT_DIR}/rke/full-cluster-state.json > ${OUTPUT_DIR}/rke/kubeController.json
  jq -cr '.currentState.rkeConfig.dns' ${OUTPUT_DIR}/rke/full-cluster-state.json > ${OUTPUT_DIR}/rke/dns.json
  rm ${OUTPUT_DIR}/rke/full-cluster-state.json

  kubectl get ds -n ingress-nginx -o json > ${OUTPUT_DIR}/rke/ingress-nginx-daemonsets.json
  kubectl -n ingress-nginx exec ds/nginx-ingress-controller -- /nginx-ingress-controller --help > rke/ingress-nginx-help.txt 2>&1
}

collect_rke2_info() {
  mkdir -p "${OUTPUT_DIR}/rke2"

  jq '[ .items[] | select(.metadata.namespace == "kube-system" and .metadata.labels.component == "kube-apiserver") | .spec.containers[0].args ] | .[0]' pods.json > rke2/kube-apiserver-args.json
  jq '[ .items[] | select(.metadata.namespace == "kube-system" and .metadata.labels.component == "kube-controller-manager") | .spec.containers[0].args ] | .[0]' pods.json > rke2/kube-controller-manager-args.json
  jq '[ .items[] | select(.metadata.namespace == "kube-system" and .metadata.labels.component == "kube-proxy") | .spec.containers[0].args ] | .[0]' pods.json > rke2/kube-proxy-args.json
  jq '[ .items[] | select(.metadata.namespace == "kube-system" and .metadata.labels.component == "kube-scheduler") | .spec.containers[0].args ] | .[0]' pods.json > rke2/kube-scheduler-args.json

  kubectl get validatingwebhookconfigurations.admissionregistration.k8s.io -o json > rke2/validatingwebhookconfigurations.json
  kubectl -n kube-system exec ds/rke2-ingress-nginx-controller -- /nginx-ingress-controller --help > rke2/ingress-nginx-help.txt 2>&1
  kubectl get configmap -n kube-system node-local-dns -o json > rke2/node-local-dns-configmap.json

  kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status -o json > rke2/cilium-status.json
  if [ ! -s rke2/cilium-status.json ]; then
    rm rke2/cilium-status.json
  fi
  kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list -o json > rke2/cilium-dbg-service-list.json
  if [ ! -s rke2/cilium-dbg-service-list.json ]; then
    rm rke2/cilium-dbg-service-list.json
  fi

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


collect_harvester_info() {
  mkdir -p "${OUTPUT_DIR}/harvester"

  kubectl get settings.harvesterhci.io -o json > harvester/settings.json
  kubectl get deploy -n harvester-system -o json > harvester/harvester-system-deploy.json
}


collect_upstream_cluster_info() {
  kubectl get features.management.cattle.io -o json > features-management.json
  kubectl get bundledeployments.fleet.cattle.io -A -o json > bundledeployment.json
  kubectl get deployments.apps -A -o json | jq -cr '.items[] | select(.metadata.name == "secrets-store-sync-controller-manager") | .spec.template.spec.containers[0].image | split(":")[1] | sub("^v"; "") | split(".") | map(tonumber) | (.[0] * 10000 + .[1] * 100 + .[2])' > secrets-store-sync-controller-manager-version
  if [ ! -s secrets-store-sync-controller-manager-version ]; then
    rm secrets-store-sync-controller-manager-version
  fi
  kubectl get configmap -n kube-system cattle-controllers -o json > cattle-controllers-configmap.json
  kubectl get bundles.fleet.cattle.io -n fleet-local  -o json > fleet-local-bundle.json
  kubectl get apps.catalog.cattle.io -n cattle-resources-system -o json > cattle-resources-system-apps.json
  kubectl get backup.resources.cattle.io -o json > backup.json

  rancher_version=$(kubectl get settings.management.cattle.io server-version -o json | jq -cr '.value | sub("^v"; "")')
  rancher_deployment_name=$(kubectl -n cattle-system get deployments.apps -o json | jq -cr ".items[] | select(.metadata.labels.chart == \"rancher-$rancher_version\") | .metadata.name")
  jq "[.items[] | select(.metadata.namespace == \"cattle-system\" and .metadata.labels.app == \"$rancher_deployment_name\") | .spec.nodeName] | unique | length" pods.json > unique-rancher-pod-count-by-node
  number_of_rancher_pods=$(jq -cr "[.items[] | select(.metadata.namespace == \"cattle-system\" and .metadata.labels.app == \"$rancher_deployment_name\") | .metadata.name] | length" pods.json)
  kubectl get deployments.apps $rancher_deployment_name -n cattle-system -o json | jq -cr '.spec.template.spec.containers[0].env[] | select(.name=="AUDIT_LEVEL") | .value' > auditlog-level
  if [ ! -s auditlog-level ]; then
    rm auditlog-level
  fi

  kubectl get settings.management.cattle.io install-uuid -o json > settings-install-uuid.json
  kubectl get settings.management.cattle.io ui-brand -o json > settings-ui-brand.json
  kubectl get nodes.management.cattle.io -A -o json > nodes-cattle.json
  kubectl get --no-headers tokens.management.cattle.io | wc -l > token-count.txt
  kubectl get roletemplates -o json > roletemplates.json
  kubectl get clusterrole -o json > clusterrole.json
  kubectl get machines.cluster.x-k8s.io -n fleet-default -o json > machines.json
  kubectl get clusters.provisioning.cattle.io -A -o json > clusters.provisioning.cattle.io.json
  kubectl exec deployments/rancher -n cattle-system -- ls -l /var/lib/rancher > var-lib-rancher.txt
}

collect_downstream_cluster_info() {
  kubectl -n cattle-system exec deployments/cattle-cluster-agent -- ls -l /var/lib/rancher/ > var-lib-rancher.txt
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

  kubectl get backuptargets.longhorn.io -n longhorn-system -o json > apps/longhorn-backuptargets.json
  if [ ! -s apps/longhorn-backuptargets.json ]; then
    rm apps/longhorn-backuptargets.json
  fi
}

collect_cluster_info() {
  collect_common_cluster_info
  if [ "${IS_UPSTREAM_CLUSTER}" == "true" ]; then
    collect_upstream_cluster_info
  else
    collect_downstream_cluster_info
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
    "harvester")
      collect_harvester_info
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

move_ip_map() {
  if "${OBFUSCATE}" == "true"; then
    echo "moving map"
    mv ip_map.json ${SONOBUOY_RESULTS_DIR}/
  else
    echo "nothing to move"
  fi
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

  #Handle Obfuscate case
  if "${OBFUSCATE}" == "true"; then
    echo "obfuscation enabled"
    echo "true" > "${OUTPUT_DIR}/obfuscate_data"

    json_list=("nodes.json" "cattle-system-deploy.json" "nodes-cattle.json" "services-default.json" "crds.json" "pods.json")

    for file in ${json_list[@]}; do
      prefix='obf_'
      newfile="${prefix}${file}"
      obfuscate_json.py $file $newfile
      echo "moving ${newfile} to ${file}"
      rm $file
      mv $newfile $file
    done
  fi

  delete_sensitive_info
  move_ip_map

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
