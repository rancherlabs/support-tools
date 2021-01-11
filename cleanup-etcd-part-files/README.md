# Workaround ETCD Snapshots Part Files Issue
To workaround issue [gh-30662](https://github.com/rancher/rancher/issues/30662) please select one of the following deployment options.

## Option A - cleanup file temp files
This script runs on each etcd node in a while true loop every 5 minutes looking for leftover part files. If it finds part files older than 15 minutes, it will delete them. This is to prevent deleting a part file that is currently in-use.

### Changes to restore process
None, the restore process is unchanged.

### Installation
```
kubectl apply -f delete-part-files.yaml
```

## Option B - alternative s3 snapshots
This script replaces the recurring snapshot functionality in RKE with a Kubernetes job that runs every 12 hours.

### Changes to restore process
- You will need to manually take a new snapshot
- Download the snapshot from S3 on all etcd nodes
- Rename the old snapshot to the new snapshot filename
- Restore the S3 snapshot in Rancher UI by selecting the new snapshot name

### Installation
- Disable recurring snapshots in Rancher/RKE
- At a minimum, `alt-s3-sync.yaml` must be modified (remember to base64 the values) to reflect the s3 details
```
kubectl apply -f alt-s3-sync.yaml
```
