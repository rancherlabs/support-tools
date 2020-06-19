#!/bin/bash

echo "Rancher Systems Summary Report"
echo "=============================="
echo "Run on `date`"
echo

if [[ ! -z $KUBERNETES_PORT ]];
then
  RANCHER_POD=$(kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=id:metadata.name | head -n1)
  KUBECTL_CMD="kubectl -n cattle-system exec ${RANCHER_POD} -- kubectl"
else
  if $(command -v k3s >/dev/null 2>&1)
  then
    KUBECTL_CMD="k3s kubectl"
  else
    # Get docker id for rancher single node install
    DOCKER_ID=$(docker ps | grep "rancher/rancher:" | cut -d' ' -f1)
    if [ -z "${DOCKER_ID}" ]
    then
      # Get docker id for rancher ha install
      DOCKER_ID=$(docker ps | grep "k8s_rancher_rancher" | cut -d' ' -f1 | head -1)
      if [ -z "${DOCKER_ID}" ]
      then
        echo "Could not find Rancher 2 container, exiting..."
        exit -1
       fi
    fi
    KUBECTL_CMD="docker exec ${DOCKER_ID} kubectl"
  fi
fi

echo "Rancher version: $(${KUBECTL_CMD} get settings.management.cattle.io server-version --no-headers -o custom-columns=version:value)"
echo "Rancher id: $(${KUBECTL_CMD} get settings.management.cattle.io install-uuid --no-headers -o custom-columns=id:value)"
echo

${KUBECTL_CMD} get clusters.management.cattle.io -o custom-columns=Cluster\ Id:metadata.name,Name:spec.displayName,K8s\ Version:status.version.gitVersion,Provider:status.driver,Created:metadata.creationTimestamp,Nodes:status.appliedSpec.rancherKubernetesEngineConfig.nodes[*].address

CLUSTER_IDS=$(${KUBECTL_CMD} get cluster.management.cattle.io --no-headers -o custom-columns=id:metadata.name)

for ID in $CLUSTER_IDS
do
  CLUSTER_NAME=$(${KUBECTL_CMD} get cluster.management.cattle.io ${ID} --no-headers -o custom-columns=name:spec.displayName)
  NODE_COUNT=$(${KUBECTL_CMD} get nodes.management.cattle.io -n ${ID} --no-headers 2>/dev/null | wc -l )
  ((TOTAL_NODE_COUNT += NODE_COUNT))
  echo
  echo "--------------------------------------------------------------------------------"
  echo "Cluster: ${CLUSTER_NAME} (${ID})"
  ${KUBECTL_CMD} get nodes.management.cattle.io -n ${ID} -o custom-columns=Node\ Id:metadata.name,Address:status.internalNodeStatus.addresses[*].address,Role:status.rkeNode.role[*],CPU:status.internalNodeStatus.capacity.cpu,RAM:status.internalNodeStatus.capacity.memory,OS:status.dockerInfo.OperatingSystem,Docker\ Version:status.dockerInfo.ServerVersion,Created:metadata.creationTimestamp
  echo "Node count: ${NODE_COUNT}"
done
echo "--------------------------------------------------------------------------------"
echo "Total node count: ${TOTAL_NODE_COUNT}"
