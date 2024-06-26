# SURE-5880 Support Script

## Purpose

This script is designed to be used to upgrade EKS clusters using kubectl. Its been specifically designed for Rancher v2.6.10 and upgrading EKS clusters from 1.22 to 1.23 (whilst a UI issue prevents this).

## Requirements

This script requires the following:

- jq
- kubectl

## Usage

1. Open a terminal
2. Export environment variables for the path to the kubeconfig for your Rancher cluster

```bash
export RANCHER_KUBE="<PATH TO YOUR RANCHER KUBECONFIG>"
```

### Upgrading EKS Clusters

1. Get a list of your EKS clusters using this command

```bash
# For v2 
./eks-support.sh list -k $RANCHER_KUBE
# For v1
./eks-support.sh list -k $RANCHER_KUBE --kev1
```

2. For each EKS cluster you want to upgrade run the following command:

```bash
# For v2 
./eks-support.sh upgrade -k $RANCHER_KUBE --from 1.22 --to 1.23 --nname <EKS_CLUSTER_NAME>
# For v1
./eks-support.sh upgrade -k $RANCHER_KUBE --from 1.22 --to 1.23 --name <EKS_CLUSTER_NAME> --kev1
```

> Replace the values of --from, --to and --name with your values.

### Unsetting Node Groups as managed fields for imported EKS Clusters (only for KEv2)

```bash
# For v2
./eks-support.sh unset_nodegroups -k $RANCHER_KUBE --name <EKS_CLUSTER_NAME>
```
