# Searching for orphaned machine object
This script is designed to walk through all clusters in a Rancher install to find orphaned machine objects.

NOTE: This script is read-only does not make any changes to the cluster, node, or Rancher.

## Script logic
This script connects to the Rancher API using a key and the Rancher URL. It will then create a list of all clusters. It will then generate a kubeconfig for each cluster. It then walks through each machine objects and tries to match it to a node in the cluster using kubectl get nodes.

## Install

### Create Rancher API keys
- Please the steps listed in [here](https://rancher.com/docs/rancher/v2.x/en/user-settings/api-keys/#creating-an-api-key) to create an API key.
  NOTE: This key should have global permissions to list clusters and generate a Kubeconfig.
- Example output
```
Endpoint: https://rancher.example.com/v3
Access Key: token-abcde
Secret Key: abcdefghijklmnopqrstuvwxyz1234567890123456789012345678
```

### Setup credentials and deploy the workload
- Please run the following to create a namespace
```
kubectl create namespace detect-orphaned-machines
```

- Please run the following to create a secret using the API keys created earlier.
```
kubectl -n detect-orphaned-machines create secret generic rancher-api-key \
  --from-literal=cattle-server="https://rancher.example.com/v3" \
  --from-literal=access-key="token-abcde" \
  --from-literal=secret-key="abcdefghijklmnopqrstuvwxyz1234567890123456789012345678"
```

- Deploy configmap
```
kubectl -n detect-orphaned-machines create configmap detect-orphaned-machines --from-file main.sh
```

- Deploy workload
```
kubectl apply -n detect-orphaned-machines -f workload.yaml
```

## Example messages

### A healthy cluster
```
OK: a1ubk8sl03 found in a1-k8s-lab / c-7mf5d
OK: a1ubk8sl02 found in a1-k8s-lab / c-7mf5d
OK: a1ubk8sl01 found in a1-k8s-lab / c-7mf5d
```

### Broken globalDNS record
```
OK: m-30432d5ca359 was matched with fmr-rancher-02 in lab-rancher / c-ndnxw
CRITICAL: m-30432d5ca399 was matched with lab-rancher-99 but could not be found in lab-rancher / c-ndnxw
OK: m-403894c31e94 was matched with fmr-rancher-03 in lab-rancher / c-ndnxw
OK: m-9ca344698600 was matched with fmr-rancher-01 in lab-rancher / c-ndnxw
```
