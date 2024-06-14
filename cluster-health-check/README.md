# Cluster Health Check

The script needs to be downloaded and run on one of the following servers.

* A server or workstation with kubectl access to the local cluster.
* Directly on one of the local cluster nodes using the `root` user or using `sudo`.
* As a k8s deployment on the cluster.

## How to use

* Download the script and save as: `cluster-health.sh`
* Make sure the script is executable: `chmod +x cluster-health.sh`
* Run the script: `./cluster-health.sh`

The script will create a .tar.gz log collection in /tmp by default, all flags are optional.

## Flags

```
Rancher Cluster Health Check
Usage: cluster-health.sh [ -d <directory> -k ~/.kube/config -i rancherlabs/swiss-army-knife -f -D ]

All flags are optional
-d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
-k    Override the kubeconfig (ex: ~/.kube/custom)
-f    Force collection if the minimum space isn't available
-i    Override the debug image (ex: registry.example.com/rancherlabs/swiss-army-knife)
-D    Enable debug logging"
```
