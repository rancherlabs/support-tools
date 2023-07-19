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

dedupe_principal() {
  # Run kubectl command to get the user list as JSON
  user_list=$(kubectl get users -o json)

  # Find duplicate users based on principalIds
  duplicates=$(echo "$user_list" | jq -r '.items[].principalIds[]' | sort | uniq -d)
  while IFS= read -r principal_id; do
    users_to_delete=$(echo "$user_list" | jq -r --arg principal_id "$principal_id" '[.items[] | select(.principalIds[] == $principal_id)] | sort_by(.metadata.creationTimestamp) | .[1:] | .[].metadata.name')
    if [[ -n "$users_to_delete" ]]; then
      echo "Duplicate users found for principalId: $principal_id"
      echo "Users to delete: $users_to_delete"

      if [ "$dry_run" = true ]; then
        echo "Dry run: User deletion skipped."
      else
        for user in $users_to_delete; do
          echo "Attempting to delete user: $user"
          kubectl delete user "$user"
          echo "User deleted."
        done
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

dedupe_principal

rm ./.temp_kubeconfig.yaml
