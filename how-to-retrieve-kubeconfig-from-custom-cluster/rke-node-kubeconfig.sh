#!/usr/bin/env bash

PRIVATE_REGISTRY="$1/"

# Check if controlplane node (kube-apiserver)
CONTROLPLANE=$(docker ps -q --filter=name=kube-apiserver)

# Get agent image from Docker images
RANCHER_IMAGE=$(docker inspect $(docker images -q --filter=label=io.cattle.agent=true) --format='{{index .RepoTags 0}}' | tail -1)

if [ -z $RANCHER_IMAGE ]; then
  RANCHER_IMAGE="${PRIVATE_REGISTRY}rancher/rancher-agent:v2.6.11"
fi

if [ -d /opt/rke/etc/kubernetes/ssl ]; then
  K8S_SSLDIR=/opt/rke/etc/kubernetes/ssl
else
  K8S_SSLDIR=/etc/kubernetes/ssl
fi

# Determine object type for full-cluster-state (depends on Rancher/RKE version), can be either a configmap (older versions) or a secret (newer versions)
FULL_CLUSTER_STATE_TYPE=$(docker run --rm --net=host -v $K8S_SSLDIR:/etc/kubernetes/ssl:ro --entrypoint bash $RANCHER_IMAGE -c 'kubectl --kubeconfig /etc/kubernetes/ssl/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o jsonpath='{.kind}' 2>/dev/null || kubectl --kubeconfig /etc/kubernetes/ssl/kubecfg-kube-node.yaml get secret -n kube-system full-cluster-state -o jsonpath='{.kind}' 2>/dev/null')

# Generate kubeconfig depending on object type for full-cluster-state
if [ "$FULL_CLUSTER_STATE_TYPE" = "Secret" ]; then
  docker run --rm --net=host -v $K8S_SSLDIR:/etc/kubernetes/ssl:ro --entrypoint bash $RANCHER_IMAGE -c 'kubectl --kubeconfig /etc/kubernetes/ssl/kubecfg-kube-node.yaml get secret -n kube-system full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | base64 -d | jq -r .currentState.certificatesBundle.\"kube-admin\".config | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_"' > kubeconfig_admin.yaml
elif [ "$FULL_CLUSTER_STATE_TYPE" = "ConfigMap" ]; then
  docker run --rm --net=host -v $K8S_SSLDIR:/etc/kubernetes/ssl:ro --entrypoint bash $RANCHER_IMAGE -c 'kubectl --kubeconfig /etc/kubernetes/ssl/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .currentState.certificatesBundle.\"kube-admin\".config | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_"' > kubeconfig_admin.yaml
else
  echo "Invalid type for object \"full-cluster-state\" (should be a Secret or a ConfigMap). Exiting..."
  exit 1
fi

if [ -s kubeconfig_admin.yaml ]; then
  if [ -z $CONTROLPLANE ]; then
    echo "This is supposed to be run on a node with the 'controlplane' role as it will try to connect to https://127.0.0.1:6443"
    echo "You can manually change the 'server:' parameter inside 'kubeconfig_admin.yaml' to point to a node with the 'controlplane' role"
  fi
  echo "Kubeconfig is stored at: kubeconfig_admin.yaml

You can use on of the following commands to use it:

  docker run --rm --net=host -v $PWD/kubeconfig_admin.yaml:/root/.kube/config --entrypoint bash $RANCHER_IMAGE -c 'kubectl get nodes'

  kubectl --kubeconfig kubeconfig_admin.yaml get nodes

Note: if kubectl is not available on the node, the binary can be copied from the kubelet container:
  docker cp kubelet:/usr/local/bin/kubectl /usr/local/bin/"
else
  echo "Failed to retrieve kubeconfig"
fi