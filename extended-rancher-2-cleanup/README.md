## Extended Rancher 2 cleanup
This script is designed to clean a Docker/Kubernetes node for re-use.

Note: Backup your data, use at your own risk.

```
curl -LO https://github.com/rancherlabs/support-tools/raw/master/extended-rancher-2-cleanup/extended-cleanup-rancher2.sh
chmod +x extended-cleanup-rancher2.sh --flush-images --flush-iptables
```
