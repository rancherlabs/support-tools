Credit for the logic that retrieves the KUBECONFIG goes to [Superseb](https://github.com/superseb/)

# kubecert
This script will set you up with kubectl and retrieve your local kube config for a cluster provisioned by RKE or Rancher.  Option -y will auto install kubectl and jq for linux.
Usage:
```bash
curl -LO https://github.com/rancherlabs/support-tools/raw/master/kubecert/kubecert.sh
bash ./kubecert.sh -y
```
