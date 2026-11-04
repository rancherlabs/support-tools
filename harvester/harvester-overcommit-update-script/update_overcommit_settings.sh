#!/bin/bash

KUBECONFIG=""
WAIT_TIME=10

usage() {
  echo "Usage: $0 -k|--kubeconfig <path> [-w|--wait <wait time>]"
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--kubeconfig)
      KUBECONFIG="$2"
      shift 2
      ;;
    -w|--wait)
      WAIT_TIME="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [-k|--kubeconfig <path>] [-w|--wait <wait time>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$KUBECONFIG" ]]; then
  echo "Error: --kubeconfig flag is required." >&2
  usage
fi

if [[ ! -r "$KUBECONFIG" ]]; then
  echo "Error: Kubeconfig file not found or not readable: $KUBECONFIG" >&2
  exit 1
fi

# Get overcommit-config JSON
CONFIG_JSON=$(kubectl --kubeconfig "$KUBECONFIG" get settings.harvesterhci.io overcommit-config -o jsonpath='{.value}')
CPU_RATIO=$(echo "$CONFIG_JSON" | jq -r '.cpu')
MEM_RATIO=$(echo "$CONFIG_JSON" | jq -r '.memory')

# Exit if parsing failed
if [[ -z "$CPU_RATIO" || -z "$MEM_RATIO" ]]; then
  echo "Failed to parse overcommit-config"
  exit 1
fi

echo "Applying overcommit settings: CPU=$CPU_RATIO%, MEM=$MEM_RATIO%"

# Iterate over all VMs
kubectl --kubeconfig "$KUBECONFIG" get vm -A -o json | jq -c '.items[]' | while read -r vm; do
  NS=$(echo "$vm" | jq -r '.metadata.namespace')
  NAME=$(echo "$vm" | jq -r '.metadata.name')

  # Get current CPU and memory limits
  CPU_REQ=$(echo "$vm" | jq -r '.spec.template.spec.domain.resources.limits.cpu')
  MEM_REQ=$(echo "$vm" | jq -r '.spec.template.spec.domain.resources.limits.memory')

  # Convert CPU to millicores if needed
  CPU_MILLICORES=$(echo "$CPU_REQ" | grep -E 'm$' > /dev/null && echo "${CPU_REQ%m}" || echo "$((CPU_REQ * 1000))")

  # Apply overcommit ratio
  NEW_CPU_MILLICORES=$((CPU_MILLICORES * 100 / CPU_RATIO))
  NEW_CPU="${NEW_CPU_MILLICORES}m"

  # Convert memory string to bytes
  MEM_UNIT=${MEM_REQ//[0-9]/}
  MEM_NUMBER=${MEM_REQ//[a-zA-Z]/}

  case "$MEM_UNIT" in
    Gi)
      MEM_BYTES=$((MEM_NUMBER * 1024 * 1024 * 1024))
      ;;
    Mi)
      MEM_BYTES=$((MEM_NUMBER * 1024 * 1024))
      ;;
    Ki)
      MEM_BYTES=$((MEM_NUMBER * 1024))
      ;;
    "")
      MEM_BYTES=$MEM_NUMBER
      ;;
    *)
      echo "Unknown memory unit in $MEM_REQ for $NS/$NAME"
      continue
      ;;
  esac

  # Apply overcommit ratio (MEM_RATIO is in percent)
  NEW_MEM_BYTES=$((MEM_BYTES * 100 / MEM_RATIO))

  # Convert back to human-readable if divisible evenly
  if (( NEW_MEM_BYTES % (1024 * 1024 * 1024) == 0 )); then
    NEW_MEM="$((NEW_MEM_BYTES / 1024 / 1024 / 1024))Gi"
  elif (( NEW_MEM_BYTES % (1024 * 1024) == 0 )); then
    NEW_MEM="$((NEW_MEM_BYTES / 1024 / 1024))Mi"
  else
    NEW_MEM="${NEW_MEM_BYTES}"
  fi

  echo "Patching VM $NS/$NAME with CPU=$NEW_CPU and Memory=$NEW_MEM"

  kubectl --kubeconfig "$KUBECONFIG" patch vm "$NAME" -n "$NS" --type merge -p \
    "{\"spec\":{\"template\":{\"spec\":{\"domain\":{\"resources\":{\"requests\":{\"cpu\":\"$NEW_CPU\",\"memory\":\"$NEW_MEM\"}}}}}}}"
done

## Check the updated values.
echo "Waiting for $WAIT_TIME seconds to allow for updated changes to reflect in the VMs."

## Simple progress bar
for ((i=1; i<=$WAIT_TIME; i++)); do
  echo -n ". "
  sleep 1
done
echo

echo "Resuming..."

kubectl --kubeconfig "$KUBECONFIG" get vm -A -o json | jq -c '.items[]' | while read -r vm; do
  NS=$(echo "$vm" | jq -r '.metadata.namespace')
  NAME=$(echo "$vm" | jq -r '.metadata.name')

  LIMITS_CPU=$(echo "$vm" | jq -r '.spec.template.spec.domain.resources.limits.cpu // "none"')
  LIMITS_MEM=$(echo "$vm" | jq -r '.spec.template.spec.domain.resources.limits.memory // "none"')

  REQUESTS_CPU=$(echo "$vm" | jq -r '.spec.template.spec.domain.resources.requests.cpu // "none"')
  REQUESTS_MEM=$(echo "$vm" | jq -r '.spec.template.spec.domain.resources.requests.memory // "none"')

  echo "------"
  echo "Updated values for VM $NS/$NAME"
  echo "  Limits: CPU=$LIMITS_CPU, Memory=$LIMITS_MEM"
  echo "  Request: CPU=$REQUESTS_CPU, Memory=$REQUESTS_MEM"

done

