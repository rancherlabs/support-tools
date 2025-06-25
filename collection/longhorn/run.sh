#!/bin/bash

# Set variables
NAMESPACE="longhorn-system"
OUTPUT_DIR="longhorn-support-bundle-$(date +%Y-%m-%d-%H-%M-%S)"
ARCHIVE_NAME="${OUTPUT_DIR}.tar.gz"

# Create directory structure
mkdir -p "${OUTPUT_DIR}/logs/${NAMESPACE}"
mkdir -p "${OUTPUT_DIR}/yamls/namespaced/${NAMESPACE}/kubernetes"
mkdir -p "${OUTPUT_DIR}/yamls/namespaced/${NAMESPACE}/longhorn"
mkdir -p "${OUTPUT_DIR}/yamls/cluster/kubernetes"
mkdir -p "${OUTPUT_DIR}/nodes"

echo "Creating support bundle for ${NAMESPACE} namespace..."

# Get cluster information
echo "Collecting cluster information..."
kubectl version --output=yaml > "${OUTPUT_DIR}/yamls/cluster/kubernetes/version.yaml"
kubectl get nodes -o yaml > "${OUTPUT_DIR}/yamls/cluster/kubernetes/nodes.yaml"

# Get detailed information about each node
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
for node in $NODES; do
  echo "Getting detailed information for node ${node}..."
  mkdir -p "${OUTPUT_DIR}/nodes/${node}"

  # Get complete node YAML
  kubectl get node "$node" -o yaml > "${OUTPUT_DIR}/nodes/${node}/node.yaml"

  # Get node description
  kubectl describe node "$node" > "${OUTPUT_DIR}/nodes/${node}/description.txt"

  # Get node metrics if available
  kubectl top node "$node" 2>/dev/null > "${OUTPUT_DIR}/nodes/${node}/metrics.txt" || echo "Metrics not available" > "${OUTPUT_DIR}/nodes/${node}/metrics.txt"

  # Get node capacity and allocatable resources
  kubectl get node "$node" -o jsonpath='{.status.capacity}' > "${OUTPUT_DIR}/nodes/${node}/capacity.json"
  kubectl get node "$node" -o jsonpath='{.status.allocatable}' > "${OUTPUT_DIR}/nodes/${node}/allocatable.json"
done

# Get all standard Kubernetes resources in the namespace (excluding secrets)
echo "Collecting standard Kubernetes resources..."
RESOURCES="pods services deployments daemonsets statefulsets configmaps persistentvolumeclaims replicasets"

for resource in $RESOURCES; do
  echo "Getting ${resource}..."
  kubectl get "$resource" -n "$NAMESPACE" -o yaml > "${OUTPUT_DIR}/yamls/namespaced/${NAMESPACE}/kubernetes/${resource}.yaml"
done

# Get all Longhorn CRDs and their instances
echo "Collecting Longhorn custom resources..."
LONGHORN_CRDS=$(kubectl get crd -o jsonpath='{range .items[?(@.spec.group=="longhorn.io")]}{.metadata.name}{"\n"}{end}')

for crd in $LONGHORN_CRDS; do
  resource_type=$(echo "$crd" | cut -d. -f1)
  echo "Getting ${resource_type}..."
  kubectl get "$crd" -n "$NAMESPACE" -o yaml > "${OUTPUT_DIR}/yamls/namespaced/${NAMESPACE}/longhorn/${resource_type}.yaml"
done

# Collect pod logs
echo "Collecting pod logs..."
PODS=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

for pod in $PODS; do
  echo "Getting logs for pod ${pod}..."
  mkdir -p "${OUTPUT_DIR}/logs/${NAMESPACE}/${pod}"

  # Get container names for the pod
  CONTAINERS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}')

  for container in $CONTAINERS; do
    echo "Getting logs for container ${container} in pod ${pod}..."
    kubectl logs "$pod" -c "$container" -n "$NAMESPACE" > "${OUTPUT_DIR}/logs/${NAMESPACE}/${pod}/${container}.log"

    # Get previous logs if available
    kubectl logs "$pod" -c "$container" -n "$NAMESPACE" --previous 2>/dev/null > "${OUTPUT_DIR}/logs/${NAMESPACE}/${pod}/${container}-previous.log" || true
  done
done

# Capture cluster events
echo "Capturing cluster events..."
kubectl get events --all-namespaces -o yaml > "${OUTPUT_DIR}/yamls/cluster/kubernetes/events.yaml"
kubectl get events -n "$NAMESPACE" -o yaml > "${OUTPUT_DIR}/yamls/namespaced/${NAMESPACE}/kubernetes/events.yaml"

# Compress the output directory
echo "Creating archive ${ARCHIVE_NAME}..."
tar -czf "$ARCHIVE_NAME" "$OUTPUT_DIR"

# Clean up the output directory
rm -rf "$OUTPUT_DIR"

echo "Support bundle created: ${ARCHIVE_NAME}"
