# longhorn-logs-collector

The script needs to be downloaded and run on one of the following servers.

* A server or workstation with kubectl access to the local cluster.
* Directly on one of the local cluster nodes using the `root` user or using `sudo`.
* As a k8s deployment on the local cluster.

## How to use

* Download the script and save as: `longhorn-pod-collector.sh`
* Make sure the script is executable: `chmod +x longhorn-pod-collector.sh`
* Run the script: `./longhorn-pod-collector.sh`

The script will create a .tar.gz log collection in /tmp by default, all flags are optional.

## Flags

```
longhorn Pod Collector
Usage: longhorn-pod-collector.sh [ -d <directory> -k KUBECONFIG -t -w -f ]

All flags are optional.

-d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
-k    Override the kubeconfig (ex: ~/.kube/custom)
-t    Enable trace logs
-w    Live tailing longhorn logs
-f    Force log collection if the minimum space isn't available."
```

## Important disclaimer

The flag `-t` will enables trace logging. This can capture sensitive information about your longhorn install, including but not limited to usernames, passwords, encryption keys, etc.
