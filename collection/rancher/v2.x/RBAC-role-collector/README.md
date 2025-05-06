# Rancher 2.x RBAC role collector

This project was created to collect RABC roles in a Kubernetes cluster to assist troubleshooting

## Usage

1. Download the script to a location from where you can run `kubectl` against the intended cluster, and save it as: `role-dump.sh`
  `curl -OLs  https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/RBAC-role-collector/role-dump.sh`
2. Set kubectl context to the cluster where you see the issue you are investigating.  You will likely want to run this against the Rancher local cluster as well as the downstream cluster where you see the issues
3. Run the script `bash ./role-dump.sh`

### What is collected

The output will contain:

- JSON files for each role type (in the following list) containing all the roles in the cluster
- Listing (`rolebindings.list`) of all the rolebindings ordered by type
- A tar.gz file that can be provided to support, an uncompressed directory will remain with all the data gathered for your inspection

Having this information and a list of the user IDs of any users affected by the issue can help in troubleshooting.

#### CRDs collected:

```
clusterroletemplatebindings
globalrolebindings
globalroles
projectroletemplatebindings
roletemplates.management.cattle.io
roletemplatebindings
clusterrolebindings
clusterroles
roletemplates.rancher.cattle.io
rolebindings
roles
```