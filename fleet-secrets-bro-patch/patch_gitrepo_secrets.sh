#!/usr/bin/env bash

DRYRUN=0

while getopts "D:" opt; do
  case $opt in
    D) DRYRUN=1;;
    \?) echo "Invalid option: -$OPTARG"; exit 1;;
  esac
done

output=$(kubectl get gitrepo -A -o custom-columns=NAMESPACE:.metadata.namespace,CLIENT:.spec.clientSecretName,HELM:.spec.helmSecretName,HELMPATHS:.spec.helmSecretNameForPaths --no-headers)

secret_combinations=()
while read -r row; do
  # Extract the namespace and potential secret names from each row
  namespace=$(echo "$row" | awk '{print $1}')
  read -r -a secrets <<< "$(echo "$row" | awk '{print $2, $3, $4}')"
  # Create a list of secret combinations for this namespace
  for secret in "${secrets[@]}"; do
    if [ "$secret" != "<none>" ]; then
      secret_combinations+=("$namespace:$secret")
    fi
  done
done <<< "$(echo "$output" | awk '{print $0}')"

# Sort and uniq the list of secret combinations
sorted_secret_combinations=($(printf "%s\n" "${secret_combinations[@]}" | sort -u))

echo "Patching unique secret combinations:"
for combination in "${sorted_secret_combinations[@]}"; do
  # Set the delimiter
  IFS=':'
  # Read the input string into two variables
  read -r namespace name <<< "$combination"
  if [ $DRYRUN -eq 1 ]; then
    echo "[DRY-RUN] Would patch secret: $namespace/$name"
  else
    echo "Patching secret: $combination"
    kubectl patch secret -n "$namespace" "$name" -p '{"metadata": {"labels": {"fleet.cattle.io/managed": "true"}}}'
  fi
done