# Workloads rescheduled to other nodes cannot get started after node unavailable
These scripts are designed to walk through all Longhorn volumes and check the `spec.nodeID` for deattached volumes. Then if `AlertOnly` is set to `True` then it was only alert on the broken volume. If `AlertOnly` is set to `False` then it will try to unset `spec.nodeID`.

## Bug
[https://github.com/longhorn/longhorn/issues/2618](Longhorn 2618)

## Install
- Deploy script as configmap
```
kubectl -n longhorn-system create configmap unset-nodeid --from-file main.sh
```

- Deploy workload
```
kubectl apply -n longhorn-system -f workload.yaml
```

## Example messages

```
OK: pvc-c50c4ba3-cbca-4e77-a52b-42b2f1654c63 is attached
WARNING: pvc-8bc785b5-3f66-4cd5-aa4d-708b07fff62b was patched and nodeID is now Unset
CRITICAL: pvc-8bc785b5-3f66-4cd5-aa4d-708b07fff62b nodeID is Test
```

`OK` - no issue found, no action taken.
`WARNING` - issue found but was able to resolve.
`CRITICAL` - issue found but couldn't resolve.