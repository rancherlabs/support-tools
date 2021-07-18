# Rancher 2.x RBAC Role Dump
This script collects a dump of every role in a cluster.  It will create a directory containing a JSON per each role type in the following list containing all the roles in the cluster and a list (`rolebindings.list`) of all the rolebindings the script sees ordered by type. It will then create a tar.gz that can be forwarded to support and leave behind an uncompressed directory of all the data gathered for your inspection.
Having this information and a list of the user IDs of any users affected by the issue can help in troubleshooting.

## CRDs collected:
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


## How to use
1. Download the script to a location from where you can run `kubectl` against the intended cluster, and save it as: `role-dump.sh`
2. Make sure the script is executable: `chmod +x role-dump.sh`
3. Set kubectl context to the cluster where you see the issue you are investigating.  You will likely want to run this against the Rancher local cluster as well as the downstream cluster where you see the issues
4. Run the script `./role-dump.sh`
