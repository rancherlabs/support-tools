## Extended Rancher 2 Cleanup
This script is designed to clean a node provisioned by Rancher/RKE, and re-use the node again.

**Note** for k3s nodes, use the [/usr/local/bin/k3s-killall.sh](https://rancher.com/docs/k3s/latest/en/upgrades/killall/) created during installation.

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

  -f | --flush-images       Cleanup all container images
  -i | --flush-iptables     Flush all iptables rules (includes a Docker restart)
  -h                        This help menu

  !! Warning, this script removes containers and all data specific to Kubernetes and Rancher
  !! Backup data as needed before running this script, and use at your own risk.
```