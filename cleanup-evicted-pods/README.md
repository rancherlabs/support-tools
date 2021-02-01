# Cleanup evicted pods left behind after disk pressure
When a node starts to evict pods under disk pressure, the evicted pods are left behind. All the resources like volumes, IP, containers, etc will be cleaned up and delete. But the pod object will be left behind in "evicted" status. Per upstream this is [intentional](https://github.com/kubernetes/kubernetes/issues/54525#issuecomment-340035375)

## Workaround

### Manual cleanup
```bash
kubectl get pods --all-namespaces -ojson | jq -r '.items[] | select(.status.reason!=null) | select(.status.reason | contains("Evicted")) | .metadata.name + " " + .metadata.namespace' | xargs -n2 -l bash -c 'kubectl delete pods $0 --namespace=$1'
```

### Automatic cleanup
NOTE: Uses the image `rancher/hyperkube:v1.19.6-rancher1`. This can be changed to match your cluster version by matching the same image tag rke addon jobs in the kube-system.

```bash
kubectl apply -f deploy.yaml
```
