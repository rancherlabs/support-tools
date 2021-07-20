# Cronjobs for Longhorn backups not getting scheduled after being detached
These scripts are designed to walk through all Longhorn cronjobs to repair the startingDeadlineSeconds and suspend status.

## Bug
[https://github.com/kubernetes/kubernetes/issues/42649](https://github.com/kubernetes/kubernetes/issues/42649)

## Install
- Deploy script as configmap
```
kubectl -n longhorn-system create configmap detect-orphaned-machines --from-file main.sh
```

- Deploy workload
```
kubectl apply -n longhorn-system -f workload.yaml
```

## Example messages

```
Checking on cronjob pvc-0209fba3-6584-49c8-a062-baa83ea7b967-backup-c ... Good
Checking on cronjob pvc-0209fba3-6584-49c8-a062-baa83ea7b967-snap-c ... Bad
Found broken job, the cronjob is suspend but the volume is currently attached
=========================Dumping debug data - start ================================
Status of cronjob: true
Longhorn volume name: pvc-0209fba3-6584-49c8-a062-baa83ea7b967
Longhorn volume state: attached
...
```
