#!/usr/bin/env bash

usage() {
  cat << EOF
usage: bash adjust-downstream-webhook.sh [--insecure-skip-tls-verify]

This script adjusts the rancher-webhook chart release in all clusters managed by Rancher (excluding the local cluster).
Depending on the version of Rancher, it either deletes the downstream webhook release, adjusts its version and restarts, or does nothing.
Requires kubectl and helm to be installed and available on \$PATH.
Requires rancher-charts helm repo to exist in your system. If doesn't exist please add: helm repo add rancher-charts https://charts.rancher.io && helm repo update

RANCHER_URL without a trailing slash must be set with the server URL of Rancher.
RANCHER_TOKEN must be set with an admin token generated with no scope.
To ignore TLS verification, set --insecure-skip-tls-verify.

Users also need to ensure they have the rancher-charts repo in the local Helm index.
EOF
}

if [ "$1" == "-h" ]; then
  usage
  exit 0
fi

delete_webhook() {
  cluster="$1"
  current_chart=$(helm list -n cattle-system -l name=rancher-webhook | tail -1 | cut -f 6)
  echo "Deleting $current_chart from cluster $cluster."
  helm uninstall rancher-webhook -n cattle-system
}

replace_webhook() {
  cluster="$1"
  new_version="$2"

  echo "Updating the agent to make it remember the min version $new_version of rancher-webhook, so that it can deploy it when needed in the future in cluster $cluster."
  kubectl set env -n cattle-system deployment/cattle-cluster-agent CATTLE_RANCHER_WEBHOOK_MIN_VERSION="$new_version"

  helm get values -n cattle-system rancher-webhook -o yaml > current_values.yaml
  echo "Re-installing rancher-webhook to use $new_version in cluster $cluster."
  helm upgrade --install rancher-webhook rancher-charts/rancher-webhook -n cattle-system --version "$new_version" --values current_values.yaml
  rm -f current_values.yaml
}

adjust_webhook() {
  cluster="$1"
  rancher_version="$2"

  if [[ "$rancher_version" =~ 2\.6\.13 ]]; then
    replace_webhook "$cluster" 1.0.9+up0.2.10
  elif [[ "$rancher_version" =~ 2\.6\.[0-9]$ ]] || [[ "$rancher_version" =~ 2\.6\.1[0-2]$ ]]; then
    delete_webhook "$cluster"
  elif [[ "$rancher_version" =~ 2\.7\.[0-1]$ ]]; then
    delete_webhook "$cluster"
  elif [[ "$rancher_version" =~ 2\.7\.2 ]]; then
    replace_webhook "$cluster" 2.0.2+up0.3.2
  elif [[ "$rancher_version" =~ 2\.7\.3 ]]; then
    replace_webhook "$cluster" 2.0.3+up0.3.3
  elif [[ "$rancher_version" =~ 2\.7\.4 ]]; then
    replace_webhook "$cluster" 2.0.4+up0.3.4
  elif [[ "$rancher_version" =~ 2\.[7-9]\..* ]]; then
    # This matches anything else above 2.7, including 2.8.x and 2.9.x.
    echo "No need to delete rancher-webhook, given Rancher version $rancher_version."
    echo "Ensuring CATTLE_RANCHER_WEBHOOK_MIN_VERSION is set to an empty string."
    kubectl set env -n cattle-system deployment/cattle-cluster-agent CATTLE_RANCHER_WEBHOOK_MIN_VERSION=''
  else
    echo "Nothing to do, given Rancher version $rancher_version."
  fi
}

if [ -n "$DEBUG" ]
then
  set -x
fi

if [[ -z "$RANCHER_TOKEN" || -z "$RANCHER_URL" ]]
then
  echo "Required environment variables aren't properly set."
  usage
  exit 1
fi

kubeconfig="
apiVersion: v1
kind: Config
clusters:
- name: \"local\"
  cluster:
    server: \"$RANCHER_URL\"

users:
- name: \"local\"
  user:
    token: \"$RANCHER_TOKEN\"


contexts:
- name: \"local\"
  context:
    user: \"local\"
    cluster: \"local\"

current-context: \"local\"
"

echo "$kubeconfig" >> .temp_kubeconfig.yaml
# helm will complain if these are group/world readable
chmod g-r .temp_kubeconfig.yaml
chmod o-r .temp_kubeconfig.yaml
export KUBECONFIG="$(pwd)/.temp_kubeconfig.yaml"

if [[ "$1" == "--insecure-skip-tls-verify" ]]
then
  kubectl config set clusters.local.insecure-skip-tls-verify true
fi

rancher_version=$(kubectl get setting server-version -o jsonpath='{.value}')
if [[ -z "$rancher_version" ]]; then
  echo 'Failed to look up Rancher version.'
  exit 1
fi

clusters=$(kubectl get clusters.management.cattle.io -o jsonpath="{.items[*].metadata.name}")
for cluster in $clusters
do
  if [ "$cluster" == "local" ]
  then
    echo "Skipping deleting rancher-webhook in the local cluster."
    continue
  fi
  kubectl config set clusters.local.server "$RANCHER_URL/k8s/clusters/$cluster"
  adjust_webhook "$cluster" "$rancher_version"
done

rm .temp_kubeconfig.yaml
