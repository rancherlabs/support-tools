#!/usr/bin/env bash
set -euo pipefail

if [[ -z $(which jq 2>/dev/null) ]]; then
    echo "jq is required to run this script"
    exit 1
fi

CSI_SECRET_TEMPLATE=$(cat <<EOF
{
  "apiVersion": "v1",
  "stringData": {
    "csi-vsphere.conf": "[Global]\ncluster-id = \"{{clusterId}}\"\nuser = \"%username%\"\npassword = \"%password%\"\nport = \"%port%\"\ninsecure-flag = \"%insecureFlag%\"\n\n[VirtualCenter \"%host%\"]\ndatacenters = \"%datacenters%\"\n"
  },
  "kind": "Secret",
  "metadata": {
    "annotations": {
      "provisioning.cattle.io/sync-bootstrap": "true",
      "provisioning.cattle.io/sync-target-name": "rancher-vsphere-csi-credentials",
      "provisioning.cattle.io/sync-target-namespace": "kube-system",
      "rke.cattle.io/object-authorized-for-clusters": "%cluster%"
    },
    "generateName": "vsphere-secret-csi-",
    "namespace": "fleet-default"
  },
  "type": "secret"
}
EOF
)

CPI_SECRET_TEMPLATE=$(cat <<EOF
{
  "apiVersion": "v1",
  "stringData": {
    "%datacenter%.username": "%username%",
    "%datacenter%.password": "%password%"
  },
  "kind": "Secret",
  "metadata": {
    "annotations": {
      "provisioning.cattle.io/sync-bootstrap": "true",
      "provisioning.cattle.io/sync-target-name": "rancher-vsphere-cpi-credentials",
      "provisioning.cattle.io/sync-target-namespace": "kube-system",
      "rke.cattle.io/object-authorized-for-clusters": "%cluster%"
    },
    "labels": {
      "component": "rancher-vsphere-cpi-cloud-controller-manager",
      "vsphere-cpi-infra": "secret"
    },
    "generateName": "vsphere-secret-cpi-",
    "namespace": "fleet-default"
  },
  "type": "secret"
}
EOF
)

function migratedCluster() {
    local input="$1"
    local chartValues=$(jq '.spec.rkeConfig.chartValues' <<< "$input")

    # if we don't have these keys - we're fine.
    if jq -e '(has("rancher-vsphere-cpi") | not) and (has("rancher-vsphere-csi") | not)' <<<"$chartValues" >/dev/null ; then
        echo "effected charts not present - not migrating"
        echo
        return 0
    fi

    # otherwise, see if we null'd the user/pass on the appropriate charts.
    if jq -e '."rancher-vsphere-cpi".vCenter.username != "" and ."rancher-vsphere-csi".vCenter.username != ""' <<< "$chartValues" > /dev/null; then
        echo "effected charts present - migrating"
        return 1
    else
        echo "cluster already migrated - continuing"
        echo
        return 0
    fi
}

function extractCPIConfig() {
    local cluster="$1"
    local clusterName="$2"
    cpiConfig=$(jq '.spec.rkeConfig.chartValues."rancher-vsphere-cpi".vCenter' <<< "${cluster}")
    echo $cpiConfig > "./store/${clusterName}_cpi_blob.json"
    host=$(jq -r '.host // empty' <<< "${cpiConfig}")
    username=$(jq -r '.username // empty' <<< "${cpiConfig}")
    password=$(jq -r '.password // empty' <<< "${cpiConfig}")
    echo $CPI_SECRET_TEMPLATE | \
        sed "s/%cluster%/$clusterName/g" | \
        sed "s/%datacenter%/$host/g" | \
        sed "s/%username%/$username/g" | \
        sed "s/%password%/$password/g" > "./store/${clusterName}_new_cpi_secret.json"
}

function extractCSIConfig() {
    local cluster="$1"
    local clusterName="$2"
    csiConfig=$(jq '.spec.rkeConfig.chartValues."rancher-vsphere-csi".vCenter' <<< "${cluster}")
    echo $csiConfig > "./store/${clusterName}_csi_blob.json"
    host=$(jq -r '.host // empty' <<< "${csiConfig}")
    username=$(jq -r '.username // empty' <<< "${csiConfig}")
    password=$(jq -r '.password // empty' <<< "${csiConfig}")
    port=$(jq -r '.port // 443' <<< "${csiConfig}")
    insecureFlag=$(jq -r '.insecureFlag // 1' <<< "${csiConfig}")
    datacenters=$(jq -r '.datacenters // empty' <<< "${csiConfig}")
    echo $CSI_SECRET_TEMPLATE | \
        sed "s/%cluster%/$clusterName/g" | \
        sed "s/%host%/$host/g" | \
        sed "s/%username%/$username/g" | \
        sed "s/%password%/$password/g" | \
        sed "s/%port%/$port/g" | \
        sed "s/%insecureFlag%/$insecureFlag/g" | \
        sed "s\$%datacenters%\$$datacenters\$g" > "./store/${clusterName}_new_csi_secret.json"
}

function modifyChartValues() {
    local cluster="$1"
    local clusterName="$2"
    jq '.spec.rkeConfig.chartValues."rancher-vsphere-cpi".vCenter.username = "" |
      .spec.rkeConfig.chartValues."rancher-vsphere-cpi".vCenter.password = "" |
      .spec.rkeConfig.chartValues."rancher-vsphere-csi".vCenter.username = "" |
      .spec.rkeConfig.chartValues."rancher-vsphere-csi".vCenter.password = "" |
      .spec.rkeConfig.chartValues."rancher-vsphere-cpi".vCenter.credentialsSecret.name = "rancher-vsphere-cpi-credentials" |
      .spec.rkeConfig.chartValues."rancher-vsphere-cpi".vCenter.credentialsSecret.generate = false |
      .spec.rkeConfig.chartValues."rancher-vsphere-csi".vCenter.configSecret.name = "rancher-vsphere-csi-credentials" |
      .spec.rkeConfig.chartValues."rancher-vsphere-csi".vCenter.configSecret.generate = false' <<< "$cluster" > "./store/${clusterName}_sanitized.json"
}

function shouldCreateSecrets() {
  local clusterName="$1"
  if [[ $($KUBECTL get secret -n fleet-default -o json | jq '.items[] | select(.metadata.annotations["rke.cattle.io/object-authorized-for-clusters"] == "'"$clusterName"'")' | jq -s 'length') -eq "2" ]]; then
    return 1
  else
    return 0
  fi
}

KUBECTL=$(which kubectl)
clusters=$($KUBECTL get clusters.provisioning.cattle.io -n fleet-default | awk '! /NAME/ {print $1}')
rm -rf ./store
mkdir -p ./store

for clusterName in $clusters; do
    echo "Processing cluster $clusterName"
    cluster=$($KUBECTL get clusters.provisioning.cattle.io $clusterName -n fleet-default -o json)

    if migratedCluster "$cluster"; then
      continue
    fi

    echo "Backing up original cluster config for ${clusterName}"
    echo $cluster > "./store/${clusterName}_original.json"

    echo "Extracting vCenter CPI Config for $clusterName"
    extractCPIConfig "$cluster" "$clusterName"

    echo "Extracting vCenter CSI Config for $clusterName"
    extractCSIConfig "$cluster" "$clusterName"

    echo "Modifying chartValues to refer to new secrets for $clusterName"
    modifyChartValues "$cluster" "$clusterName"

    if shouldCreateSecrets "$clusterName"; then
      read -p "Create secrets for $clusterName? (y/n): " confirm
      if [[ $confirm == "y" ]]; then
        echo "Creating secrets for $clusterName"
        $KUBECTL create -f ./store/${clusterName}_new_cpi_secret.json
        $KUBECTL create -f ./store/${clusterName}_new_csi_secret.json
      else
        echo "Skipping creation of secrets for $clusterName"
      fi
    else
      echo "Secrets already exist for $clusterName"
    fi

    read -p "Apply new cluster config for $clusterName? (y/n): " confirm
    if [[ $confirm == "y" ]]; then
      echo "Applying new cluster config for $clusterName"
      $KUBECTL apply -f ./store/${clusterName}_sanitized.json
    else
      echo "Skipping application of new cluster config for $clusterName"
    fi

    echo "Original cluster config and secrets are stored in ./store if a rollback is needed."
    echo "Done with ${clusterName}"
    echo
done
