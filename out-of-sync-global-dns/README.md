# Checking for out-of-sync Global DNS records
This script is designed to walk through all the ingresses in all downstream clusters and verify the endpoint IP addresses match the IPs in the global DNS records stored on the Rancher local cluster.

NOTE: This script is read-only does not make any changes to the DNS records or ingresses.

## Script logic
This script connects to the Rancher API using a key and the Rancher URL. It will then create a list of all downstream clusters. It will then generate a kubeconfig for each cluster. It then walks through each namespace and each ingress. It looks for an annotation to find only ingresses that are configured for global DNS. It then scans all the global DNS records stored on the Rancher local cluster using the cluster-ID, project-ID, and hostname to find the matching record. Once it finds the correct record, it builds a list of IP addresses in the globalDNS. Then it creates an IP list for ingress endpoints. Finally, it compares the two lists and reports if the lists are different.

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
kubectl create namespace out-of-sync-global-dns
```

- Please run the following to create a secret using the API keys created earlier.
```
kubectl -n out-of-sync-global-dns create secret generic rancher-api-key \
  --from-literal=cattle-server="https://rancher.example.com/v3" \
  --from-literal=access-key="token-abcde" \
  --from-literal=secret-key="abcdefghijklmnopqrstuvwxyz1234567890123456789012345678"
```

- Deploy workload
```
kubectl apply -n out-of-sync-global-dns -f workload.yaml
```

NOTE: By default, the local cluster is scanned too. This can be changed by setting SKIP_LOCAL to `true` in the `workload.yaml`

## Example messages

### Healthy globalDNS record
```
OK: The IPs for ingress test2-lb in namespace test-app2 in cluster c-abcde looks to be correct.
```

### Broken globalDNS record
```
CRITICAL: We have detected a difference between the ingress IPs and the globalDNS record for ingress test-lb in namespace test-app in cluster c-abcde
```
