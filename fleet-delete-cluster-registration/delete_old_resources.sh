#!/bin/bash

namespace=${1-fleet-default}

# We output the cluster name first, then the creation timestamp, then the
# resource name for ordering to work by cluster, then by ascending creation
# timestamp, which is in "YYYY-MM-DDTHH:mm:SSZ" format.
jsonPath='{range .items[*]}{@.status.clusterName}{"_"}{@.metadata.creationTimestamp}{"_"}{@.metadata.name}{"\n"}{end}'
cluster_regs=$(kubectl get clusterregistration -o=jsonpath="$jsonPath" -n $namespace | sort)

read -ra regs -d '' <<< "${cluster_regs}"

# The only resource we do not want to delete for each cluster is the last
# element, most recently created.
for (( i = 0; i < ${#regs[@]} - 1 ; i++ )); do
    IFS=_ read -r cluster_name creation_timestamp name <<< "${regs[i]}"

    IFS=_ read -r next_cluster_name next_creation_timestamp next_name <<< "${regs[i+1]}"

    if [ $next_cluster_name = $cluster_name ]; then 
        # The most recent cluster registration is still ahead of us: deletion is safe.
        echo -n "Cluster: $cluster_name"
        echo -e "\t$(kubectl delete clusterregistration "$name" -n $namespace)"
    fi
done
