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
    local token=""
    local api_endpoint=""
    local cluster_name=""

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
        "-t" | "--token")
            shift
            token="$1"
            ;;
        "--endpoint")
            shift
            api_endpoint="$1"
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
    if [[ "$token" == "" ]]; then
        die "You must supply a api token"
    fi
    if [[ "$api_endpoint" == "" ]]; then
        die "You must supply an api endpoint"
    fi

    do_upgrade "$cluster_name" "$from" "$to" "$token" "$api_endpoint"
}

cmd_list() {
    local token=""
    local api_endpoint=""

    while [ $# -gt 0 ]; do
        case "$1" in
        "-h" | "--help")
            cmd_list_help
            exit 1
            ;;
        "-t" | "--token")
            shift
            token="$1"
            ;;
        "--endpoint")
            shift
            api_endpoint="$1"
            ;;
        *)
            die "Unknown argument: $1. Please use --help for help"
        esac
        shift
    done

    if [[ "$token" == "" ]]; then
        die "You must supply a api token"
    fi
    if [[ "$api_endpoint" == "" ]]; then
        die "You must supply an api endpoint"
    fi

    do_list "$token" "$api_endpoint"
}

cmd_status() {
    local token=""
    local api_endpoint=""
    local cluster_name=""

    while [ $# -gt 0 ]; do
        case "$1" in
        "-h" | "--help")
            cmd_status_help
            exit 1
            ;;
        "-n" | "--name")
            shift
            cluster_name="$1"
            ;;
        "-t" | "--token")
            shift
            token="$1"
            ;;
        "--endpoint")
            shift
            api_endpoint="$1"
            ;;
        *)
            die "Unknown argument: $1. Please use --help for help"
        esac
        shift
    done

    if [[ "$cluster_name" == "" ]]; then
        die "You must supply a cluster name"
    fi
    if [[ "$token" == "" ]]; then
        die "You must supply a api token"
    fi
    if [[ "$api_endpoint" == "" ]]; then
        die "You must supply an api endpoint"
    fi

    do_status "$cluster_name" "$token" "$api_endpoint"
}

## COMMANDS IMPLEMENTATIONS

do_upgrade() {
    local cluster_name="$1"
    local from="$2"
    local to="$3"
    local token="$4"
    local api_endpoint="$5"

    ensure_jq
    ensure_api_endpoint "$api_endpoint" "$token"

    say "Upgrading cluster $cluster_name to version $to"
    do_upgrade_controlplane "$cluster_name" "$from" "$to" "$token" "$api_endpoint"
}

do_upgrade_controlplane() {
    local cluster_name="$1"
    local from="$2"
    local to="$3"
    local token="$4"
    local api_endpoint="$5"

    clusters_list_url="${api_endpoint}/clusters?name=${cluster_name}"
    
    say "Getting details for cluster $cluster_name"
    output=$(curl -fsSL "${clusters_list_url}" -H "Accept: application/json" -H "Authorization: Bearer $token")
    ok_or_die "Failed to get cluster ${cluster_name} details. Error: $?, command output: ${output}"
    
    num_records=$(jq ".pagination.total" -r <<< "$output")
    if [[ "$num_records" != "1" ]]; then
        die "Expected to find 1 cluster but found $num_records, not upgrading"
    fi

    say "Checking cluster is active and with expected version $from"
    current_version=$(jq ".data[0].eksConfig.kubernetesVersion" -r <<< "$output")
    current_state=$(jq ".data[0].state" -r <<< "$output")
    cluster_id=$(jq ".data[0].id" -r <<< "$output")

    if [[ "$current_version" != "$from" ]]; then
        die "Expected EKS cluster to be version $from but got $current_version, not upgrading"
    fi
    if [[ "$current_state" != "active" ]]; then
        die "Expected EKS cluster to be in 'active' state but got $current_state, not upgrading"
    fi

    say "Sending request to upgrade cluster $cluster_name ($cluster_id) to $to"
    cluster_url="${api_endpoint}/clusters/${cluster_id}"

    body="{ \"name\": \"$cluster_name\", \"eksConfig\": { \"kubernetesVersion\": \"$to\"}}"

    output=$(curl -fsSL -X PUT "${cluster_url}" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$body")
    ok_or_die "Failed to apply update for ${cluster_name}. Error: $?, command output: ${output}"
}

do_list() {
    local token="$1"
    local api_endpoint="$2"

    ensure_jq
    ensure_api_endpoint "$api_endpoint" "$token"

    say "Getting EKS clusters from Rancher"

    list_url="$api_endpoint/clusters?driver=EKS"
    output=$(curl -fsSL ${list_url} -H "Accept: application/json" -H "Authorization: Bearer $token")
    clusters=$(jq '.data[] | [.id, .name, .eksConfig.kubernetesVersion, .state] | @csv' -r <<< "$output") 
    
    say "Found the following EKS clusters"
    echo "id,name,version,state"
    echo "$clusters"
}

do_status() {
    local cluster_name="$1"
    local token="$2"
    local api_endpoint="$3"

    clusters_list_url="${api_endpoint}/clusters?name=${cluster_name}"
    
    output=$(curl -fsSL "${clusters_list_url}" -H "Accept: application/json" -H "Authorization: Bearer $token")
    ok_or_die "Failed to get cluster ${cluster_name} details. Error: $?, command output: ${output}"
    
    num_records=$(jq ".pagination.total" -r <<< "$output")
    if [[ "$num_records" != "1" ]]; then
        die "Expected to find 1 cluster but found $num_records, not upgrading"
    fi

    current_version=$(jq ".data[0].eksConfig.kubernetesVersion" -r <<< "$output")
    current_state=$(jq ".data[0].state" -r <<< "$output")
    cluster_id=$(jq ".data[0].id" -r <<< "$output")

    say "Cluster $cluster_name is $current_state (version $current_version)"
}

## COMMAND HELP FUNCTIONS

cmd_upgrade_help() {
	cat <<EOF
  upgrade              Upgrade an EKS clusters version using API calls
    OPTIONS:
      --name, -n       The name of the cluster to upgrade.
      --from           The version number to upgrade from.
      --to             The version number to upgrade to.
      --token, -t      The Rancher API bearer token to use.
      --endpoint       The Rancher API endpoint.
EOF
}

cmd_list_help() {
	cat <<EOF
  list                 List the EKS cluster ids.
    OPTIONS:
      --token, -t      The Rancher API bearer token to use.
      --endpoint       The Rancher API endpoint.
EOF
}

cmd_status_help() {
	cat <<EOF
  status               Display the status of a EKS cluster
    OPTIONS:
      --name, -n       The name of the cluster to upgrade.
      --token, -t      The Rancher API bearer token to use.
      --endpoint       The Rancher API endpoint.
EOF
}

cmd_help() {
	cat <<EOF
WARNING: ONLY USE AS DIRECTED BY SUSE SUPPORT

usage: $0 <COMMAND> <OPTIONS>
Script to upgrade EKS clusters using API calls to Rancher.
COMMANDS:
EOF

	cmd_list_help
	cmd_upgrade_help
    cmd_status_help
}

## ENSURE FUNCS

ensure_jq() {
    output=$(which jq 2>&1)
    ok_or_die "jq not found. Please install. Error: $?, command output: ${output}"
}

ensure_curl() {
    output=$(which curl 2>&1)
    ok_or_die "cURL not found. Please install. Error: $?, command output: ${output}"
}

ensure_api_endpoint() {
    endpoint="$1"
    token="$2"
    
    ensure_curl

    output=$(curl --head --silent --fail -H "Authorization: Bearer $token" $endpoint)
    
    ok_or_die "Failed querying API endpoint: $endpoint. Error: $?, command output: ${output}"
}

say_warn "ONLY USE THIS SCRIPT AS DIRECTED BY SUSE SUPPORT"
main "$@"