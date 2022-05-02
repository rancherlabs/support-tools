# Rancher resource cleanup script

**Warning**
```
THIS WILL DELETE ALL RESOURCES CREATED BY RANCHER
MAKE SURE YOU HAVE CREATED AND TESTED YOUR BACKUPS
THIS IS A NON REVERSIBLE ACTION
```

This script will delete all Kubernetes resources belonging to/created by Rancher (including installed tools like logging/monitoring/opa gatekeeper/etc). Note: this does not remove any Longhorn resources.

## Using the cleanup script

### Run as a Kubernetes Job (preferred)

* Deploy the job using `kubectl create -f rancher-cleanup.yaml`
* Watch logs using `kubectl  -n kube-system logs -l job-name=cleanup-job  -f`

### Run the script on a Linux node

* Set KUBECONFIG enviroment variable to working kubeconfig file
* Run `cleanup.sh` as shown below, it should be POSIX compatible so `chmod +x cleanup.sh && ./cleanup.sh` or `sh cleanup.sh` should work.

## Verify

The script `verify.sh` will use the similar commands to retrieve the resources that need to be deleted, so the output should be empty after running `cleanup.sh`.

## Runtime

Testing rounds on AKS took around 60 minutes to complete using Cloud Shell, when using node access as described on https://docs.microsoft.com/en-us/azure/aks/node-access#create-an-interactive-shell-connection-to-a-linux-node, it should have the same performance as on RKE1.

Testing rounds on RKE1/RKE2/K3S took around 5 minutes to complete. (running on the Kubernetes node itself to reduce latency)
