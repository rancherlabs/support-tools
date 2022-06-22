#!/bin/sh

datenow="$(date "+%F-%H-%M-%S")"
outputdir="/tmp/enum-cattle-resources-$datenow"
export outputdir

usage() {
    printf "Rancher Resource Enumerator"
    printf "Usage: ./rancher-resource-enumerator.sh\n"
    printf " -h                               Display this help message.\n"
    printf " -d <directory>                   Path to output directory (default: /tmp/enum-cattle-resources-<timestamp>).\n"
    exit 0
}

while getopts :d:h opt; do
    case ${opt} in
      h)
         usage
        ;;
      d) path=${OPTARG}
         outputdir="$path-$datenow"
         export outputdir
       ;;
      *)
          printf "Invalid Option: %s.\n" "$1"
          usage
       ;;
     esac
done 

# Create output directory
echo "Output directory set to $outputdir"
mkdir -p "$outputdir"

# Get cluster resources
namespaces="$(kubectl get ns --no-headers -o jsonpath='{.items[*].metadata.name}')"
export namespaces
kubectl api-resources --verbs=list --namespaced=false -o name | grep cattle.io | xargs -I _ sh -c "echo (cluster) enumerating _ resources...; kubectl get _ -o custom-columns=KIND:.kind,NAME:.metadata.name --no-headers=true --ignore-not-found=true >> $outputdir/_"  

# Get namespaced resources
for n in $namespaces
do
    kubectl api-resources --verbs=list --namespaced=true -o name | grep cattle.io | xargs -I _ sh -c "echo (namespaced) enumerating _ resources in $n...; kubectl get _ -n $n -o custom-columns=KIND:.kind,NAME:.metadata.name,NAMESPACE:.metadata.namespace --no-headers=true --ignore-not-found=true >> $outputdir/_"  
done

# Get total counts
countfiles="$outputdir/*"
export countfiles
for f in $countfiles
do
    echo 'counting totals...'; wc -l "$f" >> "$outputdir"/totals
done
