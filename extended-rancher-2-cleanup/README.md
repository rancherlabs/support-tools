## Extended Rancher 2 Cleanup

This script is designed to clean a node provisioned with the RKE1 distribution using Rancher or the RKE CLI.

The node will be cleaned of all state to ensure it is consistent to reuse in a cluster or other use case.

For [RKE2](https://docs.rke2.io/install/linux_uninstall/) and [K3s](https://rancher.com/docs/k3s/latest/en/installation/uninstall/) nodes, use the uninstall.sh script created during installation

> **Warning** this script will delete all containers, volumes, network interfaces, and directories that relate to Rancher and Kubernetes. It will also flush all iptables rules and optionally delete container images.

> It is important to perform pre-checks, and backup the node as needed before proceeding with any steps below.

### Running the script

#### Download the script
```bash
curl -LO https://github.com/rancherlabs/support-tools/raw/master/extended-rancher-2-cleanup/extended-cleanup-rancher2.sh
```
#### Run the script as root, or prefix with sudo
```bash
bash extended-cleanup-rancher2.sh
```

### Usage

```bash
# bash extended-cleanup-rancher2.sh -h
Rancher 2.x extended cleanup
  Usage: bash extended-cleanup-rancher2.sh [ -f -i -s ]

  All flags are optional

  -f | --skip-iptables      Skip flush of iptables rules
  -i | --delete-images      Cleanup all container images
  -s | --delete-snapshots   Cleanup all etcd snapshots
  -h                        This help menu

    !! Warning, this script flushes iptables rules, removes containers, and all data specific to Kubernetes and Rancher
    !! Docker will be restarted when flushing iptables rules
    !! Backup data as needed before running this script
    !! Use at your own risk
```
