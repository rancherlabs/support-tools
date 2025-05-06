# Rancher v2.x rancher-pod-collector

This project was created to collect output for the Rancher installation in a Rancher Management (local) cluster when troubleshooting support cases

This script needs to be downloaded and run on one of the following locations:

- A server or workstation with kubectl access to the Rancher Management (local) cluster
- Directly on one of the cluster nodes using the `root` user or using `sudo`
- As a k8s deployment on the local cluster

## Usage

- Download the script and save as: `rancher-pod-collector.sh`
- Make sure the script is executable: `chmod +x rancher-pod-collector.sh`
- Run the script: `./rancher-pod-collector.sh`

Output will be written to `/tmp` as a tar.gz archive named `<context>-<date>.tar.gz`, the default output directory can be changed with the `-d` flag.

## Flags

```
Rancher Pod Collector
Usage: rancher-pod-collector.sh [ -d <directory> -k KUBECONFIG -t -w -f ]

All flags are optional.

-d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
-k    Override the kubeconfig (ex: ~/.kube/custom)
-t    Enable trace logs
-w    Live tailing Rancher logs
-f    Force log collection if the minimum space isn't available."
```

## Important disclaimer

The flag `-t` will enables trace logging. This can capture sensitive information about your Rancher install, including but not limited to usernames, passwords, encryption keys, etc.
