#!/bin/bash
set -e

# SURE-6644 Support Script
#
# Use this script as directed by SUSE support only.

# Function to display usage instructions
usage() {
  echo "Usage: $0 [-w] [--insecure-skip-tls-verify]"
  echo "Additionally, the RANCHER_TOKEN and RANCHER_URL environment variables must be set."
}

# Function to get a list of duplicate displayNames and delete the newer of the duplicates
dedupe_displayNames() {
  # Run kubectl command to get the user list as JSON
  user_list=$(kubectl get users -o json)

  # Find duplicate users based on displayName
  duplicates=$(echo "$user_list" | jq -r '.items[].displayName' | sort | uniq -d)
  while IFS= read -r display_name; do
    user_to_delete=$(echo "$user_list" | jq -r --arg name "$display_name" '[.items[] | select(.displayName == $name)] | max_by(.metadata.creationTimestamp) | .metadata.name')
    if [[ -n "$display_name" ]]; then
      echo "Duplicate users found for displayName: $display_name"
      if [ "$dry_run" = true ]; then
        echo "Dry run: User deletion skipped."
      else
        echo "Attempting to delete user: $user_to_delete"
        kubectl delete user "$user_to_delete"
        echo "User deleted."
      fi
      echo "------------------"
    else
        echo "No duplicates found"
    fi
  done <<< "$duplicates"
}

# Initialize variables
dry_run=true
insecure_skip_tls_verify=false

# Parse command-line options using getopts
while getopts ":w-:" opt; do
  case "${opt}" in
    w)
      dry_run=false
      ;;
    -)
      case "${OPTARG}" in
        insecure-skip-tls-verify)
          insecure_skip_tls_verify=true
          ;;
        *)
          echo "Invalid option: --$OPTARG" >&2
          usage
          exit 1
          ;;
      esac
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))

if [ -n "$DEBUG" ]; then
  set -x
fi

if [[ -z "$RANCHER_TOKEN" || -z "$RANCHER_URL" ]]
then
  echo "Required environment variables, RANCHER_TOKEN and RANCHER_URL are not set."
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
chmod g-r .temp_kubeconfig.yaml
chmod o-r .temp_kubeconfig.yaml
export KUBECONFIG="$(pwd)/.temp_kubeconfig.yaml"

if [[ $insecure_skip_tls_verify == true ]]
then
  kubectl config set clusters.local.insecure-skip-tls-verify true
fi

dedupe_displayNames

rm ./.temp_kubeconfig.yaml
