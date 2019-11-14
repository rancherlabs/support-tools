#!/bin/bash

echo "Report run on `date`"
echo ""

# Get docker id for rancher single node install
DOCKER_ID=$(docker ps | grep "rancher/rancher:" | cut -d' ' -f1)

if [ -z "$DOCKER_ID" ]
then
  # Get docker id for rancher ha install
  DOCKER_ID=$(docker ps | grep "k8s_rancher_rancher" | cut -d' ' -f1 | head -1)

  if [ -z "$DOCKER_ID" ]
  then
    echo "Could not find Rancher 2 container, exiting..."
    exit -1
  fi
fi

echo "Rancher version: $(docker exec ${DOCKER_ID} kubectl get settings server-version --no-headers -o custom-columns=version:value)"
echo "Rancher id: $(docker exec ${DOCKER_ID} kubectl get settings install-uuid --no-headers -o custom-columns=id:value)"
echo ""

docker exec ${DOCKER_ID} kubectl get clusters -o custom-columns=Cluster\ Id:metadata.name,Name:spec.displayName,K8s\ Version:status.version.gitVersion,Provider:status.driver,Created:metadata.creationTimestamp,Nodes:status.appliedSpec.rancherKubernetesEngineConfig.nodes[*].address

CLUSTER_IDS=$(docker exec ${DOCKER_ID} kubectl get clusters --no-headers -o custom-columns=id:metadata.name)

for ID in $CLUSTER_IDS
do
  CLUSTER_NAME=$(docker exec ${DOCKER_ID} kubectl get cluster ${ID} --no-headers -o custom-columns=name:spec.displayName)
  echo ""
  echo "--------------------------------------------------------------------------------"
  echo "Cluster: ${CLUSTER_NAME} (${ID})"
  docker exec ${DOCKER_ID} kubectl get nodes.management.cattle.io -n $ID -o custom-columns=Node\ Id:metadata.name,Address:status.internalNodeStatus.addresses[*].address,Role:status.rkeNode.role[*],CPU:status.internalNodeStatus.capacity.cpu,RAM:status.internalNodeStatus.capacity.memory,OS:status.dockerInfo.OperatingSystem,Docker\ Version:status.dockerInfo.ServerVersion,Created:metadata.creationTimestamp
done
