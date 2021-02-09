## How to retrieve a cluster.yaml from RKE v0.2.x+ or Rancher v2.2.x+ cluster

If you misplaced/lost the `cluster.yaml` for an RKE managed cluster. You lose the ability to manage the cluster, do upgrades, add nodes, repair the cluster, etc.  

## Pre-requisites

- RKE v0.2.x or newer
- kubectl access to the cluster.
    - Please see this [documentation](https://github.com/rancherlabs/support-tools/tree/master/how-to-retrieve-kubeconfig-from-custom-cluster) for recovering a kubeconfig from an RKE cluster.

## Resolution

Run the [script](https://raw.githubusercontent.com/rancherlabs/support-tools/master/how-to-retrieve-cluster-yaml-from-custom-cluster/cluster-yaml-recovery.sh) and follow the instructions given.
