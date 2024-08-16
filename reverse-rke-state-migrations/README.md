# reverse-rke-state-migrations.sh
This script can be used to reverse RKE cluster state migrations that are performed automatically by Rancher on all downstream RKE clusters as of releases `v2.7.14`, and `v2.8.5`. Running this script should only be necessary if you have upgraded to a Rancher version at or above the aforementioned versions and need to restore Rancher back to a version that is older than the aforementioned versions. For example, you're on `v2.8.0` and you take a backup of Rancher and then upgrade to `v2.8.5`, but then you restore Rancher from your backup. In this case, you'd have to use this script to reverse the RKE cluster state migrations that would have occurred during the upgrade to `v2.8.5`.
 
## Usage
⚠️ **WARNING:** Before running this script, please ensure that **you've backed up your downstream RKE clusters**. The script **will delete `full-cluster-state` secrets from downstream RKE clusters**.
 
1. Take backups of your downstream RKE clusters.
2. Ensure you have [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl), [jq](https://jqlang.github.io/jq/), and [yq](https://mikefarah.gitbook.io/yq/#install) installed.
3. Generate a Rancher API token and use it to set the `RANCHER_TOKEN` environment variable.
4. Run the script pointing to your Rancher server URL.
 
```shell
export RANCHER_TOKEN=<your token>
./reverse-rke-state-migrations.sh --rancher-host <my-rancher.my-domain.com>
```
 
This script will iterate over all downstream RKE clusters and, for each one, it will ensure that a `full-cluster-state` ConfigMap exists inside the cluster as is expected by older versions of RKE. After doing this successfully for each of the targeted clusters, the script will remove a ConfigMap from the local cluster that marks the original migration as complete since it will effectively have been reversed.
