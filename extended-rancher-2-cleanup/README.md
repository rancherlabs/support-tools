## Extended Rancher 2 Cleanup

This script is designed to clean a node provisioned with the RKE distribution using Rancher or the RKE CLI. The node will be cleaned of all state to ensure it is consistent to reuse in a cluster or other use case.

> Please note, this script will delete all containers, volumes, network interfaces, and directories that relate to Rancher and Kubernetes. It can also optionally flush all iptables rules and delete container images. It is important to perform pre-checks, and backup the node as needed before proceeding with any steps below.

> **Note** for [RKE2](https://docs.rke2.io/install/linux_uninstall/) and [K3s](https://rancher.com/docs/k3s/latest/en/installation/uninstall/) nodes, use the uninstall.sh script created during installation.

### Running the script

```bash
curl -LO https://github.com/rancherlabs/support-tools/raw/master/extended-rancher-2-cleanup/extended-cleanup-rancher2.sh

bash extended-cleanup-rancher2.sh
```

### Usage

```bash
# bash extended-cleanup-rancher2.sh -h
Rancher 2.x extended cleanup
  Usage: bash extended-cleanup-rancher2.sh [ -i -f ]

  All flags are optional

  -f | --flush-iptables     Flush all iptables rules (includes a Docker restart)
  -i | --flush-images       Cleanup all container images
  -h                        This help menu

  !! Warning, this script removes containers and all data specific to Kubernetes and Rancher
  !! Backup data as needed before running this script, and use at your own risk.
```
