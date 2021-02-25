#!/bin/bash

if [[ ! -f kube_config_cluster.yml ]]
then
  echo "The kube_config_cluster.yml is missing"
  exit 1
fi

if [[ -f cluster.yml ]]
then
  echo "cluster.yml exists, please move or rename this file."
  exit 1
fi

echo "Checking that jq is installed"
if [ -x jq ]
then
  echo "Please download jq from https://github.com/stedolan/jq/releases/tag/jq-1.6 and install it"
  exti 1
fi

echo "Checking that yq v3.x is installed"
if [  -z  "`yq -V |grep "yq version 3"`" ]
then
  echo "Please download yq v3.x from https://github.com/mikefarah/yq/releases/tag/3.4.1 and install it"
  exit 1
fi

echo "Building cluster.yml..."
echo "Working on Nodes..."
echo 'nodes:' > cluster.yml
kubectl --kubeconfig kube_config_cluster.yml -n kube-system get configmap full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .desiredState.rkeConfig.nodes | yq r -P - | sed 's/^/  /' | \
sed -e 's/internalAddress/internal_address/g' | \
sed -e 's/hostnameOverride/hostname_override/g' | \
sed -e 's/sshKeyPath/ssh_key_path/g' >> cluster.yml
echo "" >> cluster.yml

echo "Working on services..."
echo 'services:' >> cluster.yml
kubectl --kubeconfig kube_config_cluster.yml -n kube-system get configmap full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .desiredState.rkeConfig.services | yq r -P - | sed 's/^/  /' >> cluster.yml
echo "" >> cluster.yml

echo "Working on network..."
echo 'network:' >> cluster.yml
kubectl --kubeconfig kube_config_cluster.yml -n kube-system get configmap full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .desiredState.rkeConfig.network | yq r -P - | sed 's/^/  /' >> cluster.yml
echo "" >> cluster.yml

echo "Working on authentication..."
echo 'authentication:' >> cluster.yml
kubectl --kubeconfig kube_config_cluster.yml -n kube-system get configmap full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .desiredState.rkeConfig.authentication | yq r -P - | sed 's/^/  /' >> cluster.yml
echo "" >> cluster.yml

echo "Working on systemImages..."
echo 'system_images:' >> cluster.yml
kubectl --kubeconfig kube_config_cluster.yml -n kube-system get configmap full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .desiredState.rkeConfig.systemImages | yq r -P - | sed 's/^/  /' >> cluster.yml
echo "" >> cluster.yml

echo "Building cluster.rkestate..."
kubectl --kubeconfig kube_config_cluster.yml -n kube-system get configmap full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r . > cluster.rkestate

read -n1 -rsp $'Press any key to continue run an rke up or Ctrl+C to exit...\n'
echo "Running rke up..."
rke up --config cluster.yml
