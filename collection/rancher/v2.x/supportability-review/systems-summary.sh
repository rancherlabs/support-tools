#!/bin/bash

echo "Rancher Systems Summary Report"
echo "=============================="
echo "Run on `date`"
echo

KUBECTL_CMD="kubectl -n cattle-system"

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
