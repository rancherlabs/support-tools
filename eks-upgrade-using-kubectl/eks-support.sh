#!/usr/bin/env bash

# SURE-5880 Support Script
#
# Use this script as directed by SUSE support only.

## Include Common Functions
source ./common.sh

## COMMANDS

cmd_upgrade() {
    local from=""
    local to=""
    local kubeconfig=""
    local cluster_name=""
    local kev1=false

    while [ $# -gt 0 ]; do
        case "$1" in
        "-h" | "--help")
            cmd_upgrade_help
            exit 1
            ;;
        "-n" | "--name")
            shift
            cluster_name="$1"
            ;;
        "--from")
            shift
            from="$1"
            ;;
        "--to")
            shift
            to="$1"
            ;;
        "-k" | "--kubeconfig")
            shift
            kubeconfig="$1"
            ;;
        "--kev1")
            kev1=true
            ;;
        *)
            die "Unknown argument: $1. Please use --help for help"
        esac
        shift
    done

    if [[ "$cluster_name" == "" ]]; then
        die "You must supply a cluster name"
    fi
    if [[ "$from" == "" ]]; then
        die "You must supply a version to upgrade from"
    fi
    if [[ "$to" == "" ]]; then
        die "You must supply a version to upgrade to"
    fi
    if [[ "$kubeconfig" == "" ]]; then
        die "You must supply the kubeconfig to the Rancher manager cluster"
    fi

    do_upgrade "$cluster_name" "$from" "$to" "$kubeconfig" "$kev1" 
}

cmd_unset_nodegroups() {
    local kubeconfig=""
    local cluster_name=""

    while [ $# -gt 0 ]; do
        case "$1" in
        "-h" | "--help")
            cmd_unset_nodegroups_help
            exit 1
            ;;
        "-n" | "--name")
            shift
            cluster_name="$1"
            ;;
        "-k" | "--kubeconfig")
            shift
            kubeconfig="$1"
            ;;
        *)
            die "Unknown argument: $1. Please use --help for help"
        esac
        shift
    done
        
    if [[ "$cluster_name" == "" ]]; then
        die "You must supply a cluster name"
    fi
    if [[ "$kubeconfig" == "" ]]; then
        die "You must supply the kubeconfig to the Rancher manager cluster"
    fi
    
    do_unset_nodegroups_kev2 "$kubeconfig" "$cluster_name"
}

cmd_list() {
    local kubeconfig=""
    local kev1=false

    while [ $# -gt 0 ]; do
        case "$1" in
        "-h" | "--help")
            cmd_list_help
            exit 1
            ;;
        "-k" | "--kubeconfig")
            shift
            kubeconfig="$1"
            ;;
        "--kev1")
            kev1=true
            ;;
        *)
            die "Unknown argument: $1. Please use --help for help"
        esac
        shift
    done

    if [[ "$kubeconfig" == "" ]]; then
        die "You must supply the kubeconfig to the Rancher manager cluster"
    fi

    do_list "$kubeconfig" "$kev1"
}

## COMMANDS IMPLEMENTATIONS

do_upgrade() {
    local cluster_name="$1"
    local from="$2"
    local to="$3"
    local kubeconfig="$4"
    local kev1="$5"

    ensure_jq
    ensure_kubectl

    say "Upgrading cluster $cluster_name to version $to using kubectl (kev1=$kev1)"
    if [[ $kev1 = "false" ]]; then
        do_upgrade_controlplane_kev2 "$cluster_name" "$from" "$to" "$kubeconfig"
    else
        do_upgrade_controlplane_kev1 "$cluster_name" "$from" "$to" "$kubeconfig"
    fi
}

do_upgrade_controlplane_kev1() {
    local cluster_name="$1"
    local from="$2"
    local to="$3"
    local kubeconfig="$4"

    cluster_id=$(kubectl --kubeconfig "$kubeconfig" get clusters.management.cattle.io -o json | jq -r ".items[] | select(.spec.displayName==\"$cluster_name\") | .metadata.name")
    ok_or_die "Failed to get cluster id ${cluster_name} details. Error: $?, command output: ${cluster_id}"
    if [[ "$cluster_id" == "" ]]; then
        die "Couldn't find cluster with display name $cluster_name"
    fi
    

    say "Getting details for cluster $cluster_name"
    output=$(kubectl --kubeconfig "$kubeconfig" get clusters.management.cattle.io "$cluster_id" -o json)
    ok_or_die "Failed to get cluster ${cluster_name} details. Error: $?, command output: ${output}"

    say "Checking cluster is active and with expected version $from"
    current_version=$(jq ".spec.genericEngineConfig.kubernetesVersion" -r <<< "$output")
    driver=$(jq ".status.driver" -r <<< "$output")
    provider=$(jq ".status.provider" -r <<< "$output")

    if [[ "$driver" != "amazonElasticContainerService" ]]; then
        die "Expected amazonElasticContainerService driver but got $driver, not upgrading"
    fi
    if [[ "$provider" != "eks" ]]; then
        die "Expected eks driver but got $provider, not upgrading"
    fi
    if [[ "$current_version" != "$from" ]]; then
        die "Expected EKS cluster to be version $from but got $current_version, not upgrading"
    fi

    temp_file=$(mktemp)

    cat<<EOF>$temp_file
spec:
  genericEngineConfig:
    kubernetesVersion: "$to"
EOF
    say "Patching Rancher cluster to upgrade cluster $cluster_name ($cluster_id) to $to"

    output=$(kubectl --kubeconfig "$kubeconfig" patch clusters.management.cattle.io "$cluster_id"  --patch-file "$temp_file" --type merge)
    ok_or_die "Failed to apply patch for ${cluster_name}. Error: $?, command output: ${output}"
    say "Patched cluster successfully"
}

do_upgrade_controlplane_kev2() {
    local cluster_name="$1"
    local from="$2"
    local to="$3"
    local kubeconfig="$4"

    cluster_id=$(kubectl --kubeconfig "$kubeconfig" get clusters.management.cattle.io -o json | jq -r ".items[] | select(.spec.displayName==\"$cluster_name\") | .metadata.name")
    ok_or_die "Failed to get cluster id ${cluster_name} details. Error: $?, command output: ${cluster_id}"
    if [[ "$cluster_id" == "" ]]; then
        die "Couldn't find cluster with display name $cluster_name"
    fi
    

    say "Getting details for cluster $cluster_name"
    output=$(kubectl --kubeconfig "$kubeconfig" get clusters.management.cattle.io "$cluster_id" -o json)
    ok_or_die "Failed to get cluster ${cluster_name} details. Error: $?, command output: ${output}"

    say "Checking cluster is active and with expected version $from"
    current_version=$(jq ".spec.eksConfig.kubernetesVersion" -r <<< "$output")
    driver=$(jq ".status.driver" -r <<< "$output")

    if [[ "$driver" != "EKS" ]]; then
        die "Expected EKS driver but got $driver, not upgrading"
    fi

    if [[ "$current_version" != "$from" ]]; then
        die "Expected EKS cluster to be version $from but got $current_version, not upgrading"
    fi

    temp_file=$(mktemp)

    cat<<EOF>$temp_file
spec:
  eksConfig:
    kubernetesVersion: "$to"
EOF
    say "Patching Rancher cluster to upgrade cluster $cluster_name ($cluster_id) to $to"

    output=$(kubectl --kubeconfig "$kubeconfig" patch clusters.management.cattle.io "$cluster_id"  --patch-file "$temp_file" --type merge)
    ok_or_die "Failed to apply patch for ${cluster_name}. Error: $?, command output: ${output}"
    say "Patched cluster successfully"
}

do_unset_nodegroups_kev2() {
    local cluster_name="$2"
    local kubeconfig="$1"

    cluster_id=$(kubectl --kubeconfig "$kubeconfig" get clusters.management.cattle.io -o json | jq -r ".items[] | select(.spec.displayName==\"$cluster_name\") | .metadata.name")
    ok_or_die "Failed to get cluster id ${cluster_name} details. Error: $?, command output: ${cluster_id}"
    if [[ "$cluster_id" == "" ]]; then
        die "Couldn't find cluster with display name $cluster_name"
    fi


    say "Getting details for cluster $cluster_name"
    output=$(kubectl --kubeconfig "$kubeconfig" get clusters.management.cattle.io "$cluster_id" -o json)
    ok_or_die "Failed to get cluster ${cluster_name} details. Error: $?, command output: ${output}"

    say "Checking cluster is active and imported"
    is_imported=$(jq ".spec.eksConfig.imported" -r <<< "$output")
    driver=$(jq ".status.driver" -r <<< "$output")

    if [[ "$driver" != "EKS" ]]; then
        die "Expected EKS driver but got $driver, not changing"
    fi

    if [[ "$is_imported" == "false" ]]; then
        die "Expected EKS cluster needs to be imported, not changing"
    fi

    say "Making backup for Rancher cluster $cluster_name ($cluster_id) configuration"
    kubectl --kubeconfig "$kubeconfig" get clusters.management.cattle.io "$cluster_id" -o yaml > "$cluster_id".yaml

    temp_file=$(mktemp)

    cat<<EOF>$temp_file
spec:
  eksConfig:
    nodeGroups: null
EOF
    say "Patching node groups for Rancher cluster $cluster_name ($cluster_id)"
    output=$(kubectl --kubeconfig "$kubeconfig" patch clusters.management.cattle.io "$cluster_id"  --patch-file "$temp_file" --type merge)
    ok_or_die "Failed to apply patch for ${cluster_name}. Error: $?, command output: ${output}"
    say "Patched cluster successfully"
}

do_list() {
    local kubeconfig="$1"
    local kev1="$2"

    ensure_jq
    ensure_kubectl

    say "Getting EKS clusters from Rancher (kev1=$kev1)"

    if [[ "$kev1" = "true" ]]; then
        output=$(kubectl --kubeconfig "$kubeconfig" get clusters.management.cattle.io -o json | jq '.items[] | select((.status.driver=="amazonElasticContainerService") and (.status.provider="eks")) | [.metadata.name, .spec.displayName, .spec.genericEngineConfig.kubernetesVersion] | @csv' -r)
    else
        output=$(kubectl --kubeconfig "$kubeconfig" get clusters.management.cattle.io -o json | jq '.items[] | select( .status.driver=="EKS" ) | [.metadata.name, .spec.displayName, .spec.eksConfig.kubernetesVersion] | @csv' -r)
    fi
    
    say "Found the following clusters"
    echo "$output"
}

## COMMAND HELP FUNCTIONS

cmd_upgrade_help() {
	cat <<EOF
  upgrade              Upgrade an EKS clusters version using API calls
    OPTIONS:
      --name, -n       The name of the cluster to upgrade.
      --from           The version number to upgrade from.
      --to             The version number to upgrade to.
      --kubeconfig, -k The path to the Rancher kubeconfig.
      --kev1           Specify this for a kev1 based cluster (default is false)
EOF
}

cmd_unset_nodegroup_help() {
  cat <<EOF
  unset_nodegroup      Unset nodegroups for EKS clusters
    OPTIONS:
      --name, -n       The name of the cluster to upgrade.
      --kubeconfig, -k The path to the Rancher kubeconfig.
EOF
}

cmd_list_help() {
	cat <<EOF
  list                 List the EKS cluster ids (using kubectl).
    OPTIONS:
      --kubeconfig, -k The path to the Rancher kubeconfig.
      --kev1           Specify this for a kev1 based cluster (default is false)
EOF
}


cmd_help() {
	cat <<EOF
WARNING: ONLY USE AS DIRECTED BY SUSE SUPPORT

usage: $0 <COMMAND> <OPTIONS>
Script to upgrade EKS clusters using kubectl against the Rancher Manager cluster.
COMMANDS:
EOF

	cmd_list_help
	cmd_upgrade_help
	cmd_unset_nodegroup_help
}

## ENSURE FUNCS

ensure_jq() {
    output=$(which jq 2>&1)
    ok_or_die "jq not found. Please install. Error: $?, command output: ${output}"
}

ensure_kubectl() {
    output=$(which kubectl 2>&1)
    ok_or_die "kubectl not found. Please install. Error: $?, command output: ${output}"
}

say_warn "ONLY USE THIS SCRIPT AS DIRECTED BY SUSE SUPPORT"
main "$@"
