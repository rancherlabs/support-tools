#!/bin/sh

datenow="$(date "+%F-%H-%M-%S")"
outputdir="/tmp/enum-cattle-resources-$datenow"
export outputdir

usage() {
    printf "Rancher Resource Enumerator \n"
    printf "Usage: ./rancher-resource-enumerator.sh [ -d <directory> -n <namespace> | -c | -a ]\n"
    printf " -h                               Display this help message.\n"
    printf " -a                               Enumerate all custom resources.\n"
    printf " -n <namespace>                   Only enumerate resources in the specified namespace(s).\n"
    printf " -c                               Only enumerate cluster (non-namespaced) resources.\n"
    printf " -d <directory>                   Path to output directory (default: /tmp/enum-cattle-resources-<timestamp>).\n"
    exit 0
}

# Arguments
optstring="cahd:n:"
while getopts ${optstring} opt; do
    case ${opt} in
      h) usage
        ;;
      d) path=${OPTARG}
        outputdir="$path-$datenow"
        export outputdir
        ;;
      a) all=1
        export all
        ;;
      n) namespaces=${OPTARG}
        export namespaces
        ;;
      c) cluster=1
        export cluster
        ;;
      *) printf "Invalid Option: %s.\n" "$1"
        usage
        ;;
    esac
done


# Setup
setup() {
  # Create output directory
  echo "Output directory set to $outputdir"
  mkdir -p "$outputdir"
}

# Get cluster resources
non_namespaced() {
  kubectl api-resources --verbs=list --namespaced=false -o name | grep cattle.io | xargs -I _ sh -c "echo '(cluster) enumerating _ resources...'; kubectl get _ -o custom-columns=KIND:.kind,NAME:.metadata.name --no-headers=true --ignore-not-found=true >> $outputdir/_"  
}

# Get namespaced resources
namespaced() {
  ns="$1"
  # Select all namespaces if no namespace is specified
  if [ -z "$ns" ]; then
    ns="$(kubectl get ns --no-headers -o jsonpath='{.items[*].metadata.name}')"
  fi
  # Get all custom resources for validated namespaces
  for n in $ns
  do
      kubectl get ns "$n" -o name && \
      kubectl api-resources --verbs=list --namespaced=true -o name | grep cattle.io | xargs -I _ sh -c "echo '(namespaced) enumerating _ resources in $n...'; kubectl get _ -n $n -o custom-columns=KIND:.kind,NAME:.metadata.name,NAMESPACE:.metadata.namespace --no-headers=true --ignore-not-found=true >> $outputdir/_"
  done
}

# Get total counts
totals() {
  countfiles="$outputdir/*"
  echo 'counting totals...'
  for f in $countfiles
  do
      wc -l "$f" >> "$outputdir"/totals
  done
  echo "results saved in $outputdir"
  exit 0
}

main() {
  if [ -n "$all" ]; then
    setup
    non_namespaced
    namespaced
    totals
  elif [ -n "$cluster" ]; then
    setup
    non_namespaced
    totals
  elif [ -n "$namespaces" ]; then
    setup
    namespaced "$namespaces"
    totals
  else
    usage
  fi
}

main