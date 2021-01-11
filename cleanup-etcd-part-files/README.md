# Workaround ETCD Snapshots Part Files Issue
To workaround issue [gh-30662](https://github.com/rancher/rancher/issues/30662) please one of the following deployments.

## Option A - cleanup file temp files
This script runs on each etcd node in a while true loop every 5 mins looking for leftover part files. If it finds part files older than 15mins, it will delete them. This is to prevent deleting a part file that is currently in-use.

### Installation
```
kubectl apply -f delete-part-files.yaml
```

## Option B - alternative s3 snapshots
This script replaces the recurring snapshot functionality in RKE with a Kubernetes job that runs every 12 hours.

### Installation
- Disable recurring snapshots in Rancher/RKE
- At a minimum, `alt-s3-sync.yaml` must be modified (remember to base64 the values) to reflect the s3 details.
```
kubectl apply -f alt-s3-sync.yaml
```
