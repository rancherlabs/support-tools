#!/bin/bash

namespace=${1-fleet-default}
chunk_size=${2-100}

if [ "$chunk_size" -le 1 ]; then
    chunk_size=1
fi

# We output the cluster name first, then the creation timestamp, then the
# resource name for ordering to work by cluster, then by ascending creation
# timestamp, which is in "YYYY-MM-DDTHH:mm:SSZ" format.
jsonPath='{range .items[*]}{@.status.clusterName}{"_"}{@.metadata.creationTimestamp}{"_"}{@.metadata.name}{"\n"}{end}'
cluster_regs=$(kubectl get clusterregistration -o=jsonpath="$jsonPath" -n "$namespace" | sort)

read -ra regs -d '' <<< "${cluster_regs}"

# delete_chunk deletes cluster registrations, extracting their names from $regs
# This function operates on set of indexes between first_idx (first argument)
# and last_chunk_idx (second argument), both included.
delete_chunk() {
    first_idx=$1
    last_idx=$2

    for (( i = first_idx; i < last_idx; i++ )); do
        IFS=_ read -r cluster_name creation_timestamp name <<< "${regs[i]}"
        IFS=_ read -r next_cluster_name next_creation_timestamp next_name <<< "${regs[i+1]}"

        if [[ "$next_cluster_name" = "$cluster_name" ]]; then
            # The most recent cluster registration is still ahead of us: deletion is safe.
            echo -n "Cluster: $cluster_name"
            echo -e "\t$(kubectl delete --ignore-not-found=true clusterregistration "$name" -n "$namespace")"
        fi
    done
}

declare -a pids

# The only resource we do not want to delete for each cluster is the last
# element, most recently created.
last_idx=$(( ${#regs[@]} - 1 ))
if [ $chunk_size -ge $last_idx ]; then
    chunk_size=$last_idx
fi

# Start an async deletion process for each chunk.
for (( i = 0; i < last_idx; i+= chunk_size )); do
    last_chunk_idx=$(( i + chunk_size - 1 ))
    if [ $last_chunk_idx -ge $last_idx ]; then
        last_chunk_idx="$last_idx"
    fi

    delete_chunk $i $last_chunk_idx &
    pids[${i}]=$!
done

# wait for deletion to complete on all chunks.
for pid in ${pids[@]}; do
    wait $pid
done
