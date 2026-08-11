# Longhorn Health Monitor Troubleshooting Runbook

## Overview

This runbook provides operational guidance for investigating alerts generated
by the Longhorn Health Monitor.

Use it to:

* Identify the affected Longhorn resource.
* Determine whether application availability or data redundancy is affected.
* Collect relevant Kubernetes, Longhorn, operating system, and Prometheus data.
* Apply safe remediation steps.
* Determine when escalation or recovery from backup may be required.

For descriptions of every alert and its PromQL condition, see
[Alert Reference](alert-reference.md).

> [!IMPORTANT]
> This runbook is a troubleshooting aid. It does not replace Longhorn, Rancher,
> or SUSE Storage support procedures.
>
> Test remediation steps in a non-production environment where possible.
> Preserve logs and resource definitions before making destructive changes.

---

## Table of Contents

* [Initial Response](#initial-response)
* [Determine the Affected Resource](#determine-the-affected-resource)
* [Determine the Operational Impact](#determine-the-operational-impact)
* [Common Data Collection](#common-data-collection)
* [Volume Alert Procedures](#volume-alert-procedures)
* [Replica and Engine Alert Procedures](#replica-and-engine-alert-procedures)
* [Node and Disk Alert Procedures](#node-and-disk-alert-procedures)
* [Monitoring Alert Procedures](#monitoring-alert-procedures)
* [Safe Remediation Boundaries](#safe-remediation-boundaries)
* [Escalation Data](#escalation-data)
* [Recovery Validation](#recovery-validation)

---

# Initial Response

When an alert fires, use the following sequence:

```text
Alert received
    |
    v
Identify the alert and affected resource
    |
    v
Determine application and volume impact
    |
    v
Check volume, engine, replica, node, and disk state
    |
    v
Review Kubernetes events and Longhorn logs
    |
    v
Review node storage, kernel, and network health
    |
    v
Apply the least disruptive remediation
    |
    v
Confirm alert clearance and restored redundancy
```

## 1. Record the Alert Details

Capture the following alert labels and annotations:

* Alert name
* Severity
* Volume
* PVC
* PVC namespace
* Replica
* Engine
* Node
* Disk
* Condition reason
* Alert start time
* Current metric value

The available labels depend on the metric and Longhorn version.

## 2. Confirm That the Alert Is Still Active

Check the alert in Alertmanager or Prometheus.

To query alerts from Prometheus:

```promql
ALERTS{
  alertstate="firing",
  component="longhorn"
}
```

Check the specific alert:

```promql
ALERTS{
  alertname="<alert-name>",
  alertstate="firing"
}
```

## 3. Record the Investigation Time

Record times in UTC when correlating:

* Prometheus alerts
* Kubernetes events
* Longhorn Manager logs
* Instance Manager logs
* Workload logs
* Kernel logs

Example:

```bash
date -u
```

---

# Determine the Affected Resource

## Identify Longhorn Volumes

```bash
kubectl -n longhorn-system get volumes.longhorn.io
```

Inspect a specific volume:

```bash
kubectl -n longhorn-system get \
  volumes.longhorn.io <volume-name> -o yaml
```

Describe the volume:

```bash
kubectl -n longhorn-system describe \
  volumes.longhorn.io <volume-name>
```

## Identify the Associated PVC

Longhorn volume names commonly correspond to Kubernetes PV names.

Check the PV:

```bash
kubectl get pv <volume-name> -o yaml
```

Find the PVC:

```bash
kubectl get pv <volume-name> \
  -o jsonpath='{.spec.claimRef.namespace}/{.spec.claimRef.name}{"\n"}'
```

Check the PVC:

```bash
kubectl -n <pvc-namespace> get pvc <pvc-name> -o yaml
```

## Identify Workloads Using the PVC

```bash
kubectl -n <pvc-namespace> get pods \
  -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,CLAIMS:.spec.volumes[*].persistentVolumeClaim.claimName'
```

Inspect a specific pod:

```bash
kubectl -n <pvc-namespace> describe pod <pod-name>
```

## Identify the Engine

```bash
kubectl -n longhorn-system get engines.longhorn.io -o wide
```

Inspect a specific engine:

```bash
kubectl -n longhorn-system get \
  engines.longhorn.io <engine-name> -o yaml
```

## Identify the Replicas

```bash
kubectl -n longhorn-system get replicas.longhorn.io -o wide
```

Inspect a specific replica:

```bash
kubectl -n longhorn-system get \
  replicas.longhorn.io <replica-name> -o yaml
```

## Identify the Longhorn Nodes and Disks

```bash
kubectl -n longhorn-system get nodes.longhorn.io
```

Inspect a node and its configured disks:

```bash
kubectl -n longhorn-system get \
  nodes.longhorn.io <node-name> -o yaml
```

---

# Determine the Operational Impact

## Volume State

Check the Longhorn volume state and robustness:

```bash
kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns='VOLUME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,NODE:.status.currentNodeID'
```

Interpretation:

| State      | General interpretation                                                |
| ---------- | --------------------------------------------------------------------- |
| `healthy`  | Expected replica redundancy is available.                             |
| `degraded` | The volume may remain available, but redundancy is reduced.           |
| `faulted`  | The volume may be unavailable because no usable replica is available. |
| `unknown`  | Longhorn cannot currently determine volume health.                    |

## Workload State

```bash
kubectl -n <pvc-namespace> get pods -o wide
```

Check for:

* Pods stuck in `ContainerCreating`
* Pods stuck in `Terminating`
* Mount failures
* Attach failures
* Application I/O errors
* Read-only filesystem errors
* Repeated pod restarts

Review workload events:

```bash
kubectl -n <pvc-namespace> get events \
  --sort-by='.lastTimestamp'
```

Review pod logs:

```bash
kubectl -n <pvc-namespace> logs <pod-name> \
  --all-containers \
  --since=30m
```

## Kubernetes Volume Attachments

```bash
kubectl get volumeattachments.storage.k8s.io
```

Find attachments for the affected PV:

```bash
kubectl get volumeattachments.storage.k8s.io -o yaml |
  grep -B 5 -A 15 '<volume-name>'
```

---

# Common Data Collection

## Longhorn Workloads

```bash
kubectl -n longhorn-system get pods -o wide
```

Check for:

* `CrashLoopBackOff`
* `Error`
* `Pending`
* Frequent restarts
* Pods missing from expected nodes

## Longhorn Manager Logs

```bash
kubectl -n longhorn-system logs \
  -l app=longhorn-manager \
  --prefix \
  --since=30m
```

Save recent logs:

```bash
kubectl -n longhorn-system logs \
  -l app=longhorn-manager \
  --prefix \
  --since=2h \
  > longhorn-manager.log
```

## Instance Manager Pods

```bash
kubectl -n longhorn-system get pods \
  -l longhorn.io/component=instance-manager \
  -o wide
```

Review logs for an affected Instance Manager:

```bash
kubectl -n longhorn-system logs \
  <instance-manager-pod> \
  --all-containers \
  --since=30m
```

## CSI Components

```bash
kubectl -n longhorn-system get pods \
  -l app=longhorn-csi-plugin \
  -o wide
```

Review CSI plugin logs from the affected workload node:

```bash
kubectl -n longhorn-system logs \
  <longhorn-csi-plugin-pod> \
  --all-containers \
  --since=30m
```

## Kubernetes Events

```bash
kubectl -n longhorn-system get events \
  --sort-by='.lastTimestamp'
```

Cluster-wide storage-related events:

```bash
kubectl get events -A \
  --sort-by='.lastTimestamp' |
  grep -Ei 'longhorn|volume|mount|attach|detach|filesystem|I/O'
```

## Node Conditions

```bash
kubectl get nodes -o wide
```

```bash
kubectl describe node <node-name>
```

## Node Storage

Run on the affected node:

```bash
lsblk -f
findmnt
df -h
df -i
```

Check the Longhorn disk path:

```bash
findmnt <longhorn-disk-path>
df -h <longhorn-disk-path>
df -i <longhorn-disk-path>
```

## Kernel Logs

```bash
journalctl -k --since "1 hour ago"
```

Filter storage-related errors:

```bash
journalctl -k --since "1 hour ago" |
  grep -Ei \
  'I/O error|buffer I/O|read-only|filesystem|ext4|xfs|nvme|scsi|blk|reset|timeout'
```

## System Services

Depending on the Kubernetes distribution:

```bash
systemctl status rke2-server
systemctl status rke2-agent
systemctl status k3s
systemctl status kubelet
```

Review the applicable service:

```bash
journalctl -u rke2-server --since "1 hour ago"
```

```bash
journalctl -u rke2-agent --since "1 hour ago"
```

---

# Volume Alert Procedures

## LonghornVolumeDegraded

### Objective

Determine which replica is unavailable and whether Longhorn is rebuilding a
replacement.

### Checks

1. Inspect volume robustness:

   ```bash
   kubectl -n longhorn-system get \
     volumes.longhorn.io <volume-name> -o yaml
   ```

2. List the associated replicas:

   ```bash
   kubectl -n longhorn-system get replicas.longhorn.io -o wide |
     grep '<volume-name>'
   ```

3. Check rebuild progress:

   ```promql
   longhorn_engine_rebuild_progress{
     volume="<volume-name>"
   }
   ```

4. Check the health of replica-hosting nodes:

   ```bash
   kubectl get nodes -o wide
   ```

5. Check Longhorn disk readiness and schedulability:

   ```bash
   kubectl -n longhorn-system get nodes.longhorn.io -o yaml
   ```

6. Review Longhorn Manager and Instance Manager logs.

### Decision

* **A rebuild is progressing:** Continue monitoring unless performance or
  application availability is affected.
* **A replica node is temporarily unavailable:** Restore the node and verify
  whether the replica reconnects.
* **Longhorn cannot schedule a replacement:** Check disk capacity, scheduling
  restrictions, node tags, disk tags, taints, and replica anti-affinity.
* **The same replica repeatedly fails:** Investigate the node, disk, filesystem,
  network, and Instance Manager.

### Do Not

* Do not delete additional replicas while the volume is degraded.
* Do not delete replica directories directly from the node.
* Do not restart all Longhorn components simultaneously.

---

## LonghornVolumeFaulted

### Objective

Determine whether any usable replica remains and preserve recoverable data.

### Immediate Actions

1. Stop unnecessary changes to the affected workload.
2. Preserve Longhorn resource YAML and logs.
3. Confirm whether a recent valid backup exists.
4. Do not delete replicas or the volume.

### Checks

```bash
kubectl -n longhorn-system get \
  volumes.longhorn.io <volume-name> -o yaml
```

```bash
kubectl -n longhorn-system get replicas.longhorn.io -o yaml \
  > replicas.yaml
```

```bash
kubectl -n longhorn-system get engines.longhorn.io -o yaml \
  > engines.yaml
```

Check every replica-hosting node:

```bash
kubectl get nodes -o wide
```

Review whether a replica is unavailable because of:

* Node shutdown
* Missing disk mount
* Network isolation
* Instance Manager failure
* Replica process failure
* Disk or filesystem errors

### Decision

* **Replica nodes are recoverable:** Restore node and storage connectivity
  before attempting volume recovery.
* **A usable replica exists but is not selected:** Follow the applicable
  Longhorn recovery procedure.
* **No usable replica exists:** Evaluate restoration from backup.
* **Replica state is unclear:** Preserve resources and escalate before making
  destructive changes.

> [!CAUTION]
> Incorrectly selecting, deleting, or reusing a replica can cause permanent
> data loss.

---

## LonghornVolumeRobustnessUnknown

### Objective

Determine why Longhorn cannot calculate the volume's health.

### Checks

```bash
kubectl -n longhorn-system get \
  volumes.longhorn.io <volume-name> -o yaml
```

```bash
kubectl -n longhorn-system get engines.longhorn.io -o wide |
  grep '<volume-name>'
```

```bash
kubectl -n longhorn-system get replicas.longhorn.io -o wide |
  grep '<volume-name>'
```

Check Longhorn workloads:

```bash
kubectl -n longhorn-system get pods -o wide
```

Review:

* Longhorn Manager restarts
* Instance Manager restarts
* Node connectivity
* Incomplete attach or detach operations
* Stale metrics
* Engine initialization failures

### Decision

* **The volume was recently attached or recovered:** Allow time to stabilize
  while continuing to monitor.
* **An engine or replica remains unknown:** Follow the corresponding engine or
  replica procedure.
* **Metrics are stale:** Follow
  [LonghornManagerMetricsMissing](#longhornmanagermetricsmissing).

---

## LonghornVolumeFilesystemReadOnly

### Objective

Determine whether the filesystem was remounted read-only because of storage or
filesystem errors.

### Immediate Actions

1. Identify the workload and node.
2. Reduce or stop application writes.
3. Preserve workload and kernel logs.
4. Do not run filesystem repair against a mounted filesystem.

### Checks

Check workload logs:

```bash
kubectl -n <pvc-namespace> logs <pod-name> \
  --all-containers \
  --since=30m
```

Check workload events:

```bash
kubectl -n <pvc-namespace> get events \
  --sort-by='.lastTimestamp'
```

Check the volume:

```bash
kubectl -n longhorn-system get \
  volumes.longhorn.io <volume-name> -o yaml
```

On the workload node:

```bash
journalctl -k --since "1 hour ago" |
  grep -Ei \
  'read-only|I/O error|filesystem|ext4|xfs|nvme|scsi|blk|reset|timeout'
```

Check the mount:

```bash
findmnt
mount | grep '<mount-path>'
```

### Decision

* **Kernel or device I/O errors exist:** Investigate the node and underlying
  storage before filesystem repair.
* **Longhorn volume is degraded or faulted:** Resolve Longhorn health first.
* **The filesystem is damaged:** Use an approved filesystem repair procedure
  during a maintenance window.
* **Data cannot be safely repaired:** Restore from a validated backup.

> [!CAUTION]
> Filesystem repair tools can modify or discard metadata. Confirm the
> filesystem type and preserve recoverable data before repair.

---

## LonghornVolumeActualSpaceHigh

### Objective

Determine whether growth comes from workload data, snapshots, or unexpected
Longhorn allocation.

### Checks

Query actual and configured size:

```promql
longhorn_volume_actual_size_bytes{
  volume="<volume-name>"
}
```

```promql
longhorn_volume_capacity_bytes{
  volume="<volume-name>"
}
```

Check PVC capacity:

```bash
kubectl -n <pvc-namespace> get pvc <pvc-name>
```

Check filesystem usage inside the workload:

```bash
df -h
df -i
```

Review Longhorn snapshots in the UI or with the applicable snapshot resources.

Check disk capacity hosting the replicas:

```bash
kubectl -n longhorn-system get nodes.longhorn.io -o yaml
```

### Decision

* **Application data is growing:** Apply application retention or cleanup.
* **Snapshots are accumulating:** Remove obsolete snapshots through supported
  Longhorn operations.
* **The volume is correctly sized but nearing capacity:** Expand the PVC and
  volume through a supported procedure.
* **The filesystem reports low usage but Longhorn actual size is high:**
  Investigate snapshots, deleted-but-open files, and block reclamation
  behavior.

---

# Replica and Engine Alert Procedures

## LonghornReplicaError

### Objective

Determine whether the replica can recover or must be safely replaced.

### Checks

```bash
kubectl -n longhorn-system get \
  replicas.longhorn.io <replica-name> -o yaml
```

Check the associated volume:

```bash
kubectl -n longhorn-system get \
  volumes.longhorn.io <volume-name> -o yaml
```

Check the replica-hosting node and disk:

```bash
kubectl get node <node-name>
```

```bash
kubectl -n longhorn-system get \
  nodes.longhorn.io <node-name> -o yaml
```

Review Instance Manager and kernel logs.

### Decision

* **Node or disk is temporarily unavailable:** Restore it and monitor whether
  the replica recovers.
* **Other healthy replicas exist:** Allow Longhorn to rebuild a replacement.
* **This may be the last usable replica:** Do not delete it; preserve data and
  escalate.
* **Failures recur on the same node or disk:** Investigate infrastructure
  health before rescheduling another replica there.

---

## LonghornReplicaUnknown

### Objective

Restore communication between Longhorn and the replica process.

### Checks

```bash
kubectl -n longhorn-system get \
  replicas.longhorn.io <replica-name> -o yaml
```

Check the Instance Manager:

```bash
kubectl -n longhorn-system get pods \
  -l longhorn.io/component=instance-manager \
  -o wide
```

Check node status:

```bash
kubectl get node <node-name> -o yaml
```

Review:

* Instance Manager restarts
* Longhorn Manager restarts
* Node connectivity
* Replica process startup
* Incomplete attach or detach operations

### Decision

* **The node recently restarted:** Allow the replica state to reconcile.
* **Instance Manager is unavailable:** Restore it and verify replica status.
* **State remains unknown:** Treat the replica as potentially unavailable and
  evaluate volume redundancy.

---

## LonghornEngineError

### Objective

Restore the active data path between the workload and replicas.

### Checks

```bash
kubectl -n longhorn-system get \
  engines.longhorn.io <engine-name> -o yaml
```

Check the volume and replicas:

```bash
kubectl -n longhorn-system get \
  volumes.longhorn.io <volume-name> -o yaml
```

```bash
kubectl -n longhorn-system get replicas.longhorn.io -o wide |
  grep '<volume-name>'
```

Check the engine-hosting node:

```bash
kubectl get node <node-name>
```

Review:

* Instance Manager logs
* Node CPU and memory pressure
* Network connectivity to replica nodes
* Replica health
* Kernel storage errors

### Decision

* **The node or Instance Manager failed:** Restore the component and confirm
  engine recovery.
* **All replicas are unavailable:** Follow
  [LonghornVolumeFaulted](#longhornvolumefaulted).
* **Some replicas are healthy:** Preserve them and investigate engine recovery.
* **The engine repeatedly crashes:** Collect logs and escalation data before
  repeated restarts.

---

## LonghornEngineUnknown

### Objective

Determine whether the engine is initializing, disconnected, or unavailable.

### Checks

```bash
kubectl -n longhorn-system get \
  engines.longhorn.io <engine-name> -o yaml
```

Check:

* Volume attachment state
* Engine-hosting node
* Instance Manager pod
* Longhorn Manager logs
* Replica states
* Recent attach or detach events

### Decision

* **A recent transition is still progressing:** Continue monitoring.
* **The node or Instance Manager is unavailable:** Restore it.
* **The engine remains unknown while the workload has I/O failures:** Treat it
  as an availability incident.

---

## LonghornEngineReplicaModeError

### Objective

Determine why the engine marked a replica as `ERR`.

### Checks

```bash
kubectl -n longhorn-system get \
  engines.longhorn.io <engine-name> -o yaml
```

```bash
kubectl -n longhorn-system get \
  replicas.longhorn.io <replica-name> -o yaml
```

Check:

* Replica node status
* Disk readiness
* Instance Manager logs
* Network errors between engine and replica nodes
* Kernel I/O errors
* Remaining healthy replica count

### Decision

* **The replica node is unavailable:** Restore the node.
* **The disk failed:** Move recovery toward healthy storage.
* **Other replicas remain healthy:** Allow Longhorn to create a replacement.
* **Few or no healthy replicas remain:** Avoid deletion and escalate.

---

## LonghornReplicaRebuildStalled

### Objective

Determine whether the rebuild is genuinely stalled or progressing too slowly
to register a change.

### Alert Timing

The current expression checks for no metric change during a 30-minute window
and then remains pending for another 30 minutes.

The effective detection time can therefore be approximately one hour.

### Checks

Query rebuild progress:

```promql
longhorn_engine_rebuild_progress{
  engine="<engine-name>"
}
```

Check the source and destination labels exposed by the metric.

Inspect the engine:

```bash
kubectl -n longhorn-system get \
  engines.longhorn.io <engine-name> -o yaml
```

Inspect replicas:

```bash
kubectl -n longhorn-system get replicas.longhorn.io -o wide |
  grep '<volume-name>'
```

On the source and destination nodes, check:

```bash
df -h
df -i
journalctl -k --since "1 hour ago"
```

Also check:

* Disk latency
* Network errors
* CPU and memory pressure
* Instance Manager restarts
* Destination disk capacity
* Longhorn rebuild concurrency settings

### Decision

* **Progress is increasing slowly:** Continue monitoring.
* **The destination node or disk failed:** Correct the failure before
  restarting recovery.
* **The source replica is unstable:** Preserve remaining healthy replicas.
* **Progress remains unchanged with no clear cause:** Collect support data
  before restarting or deleting the rebuilding replica.

---

# Node and Disk Alert Procedures

## LonghornNodeNotReady

### Objective

Determine whether the failure is at the Kubernetes node level or only in
Longhorn's view of the node.

### Checks

Compare Kubernetes and Longhorn status:

```bash
kubectl get node <node-name> -o yaml
```

```bash
kubectl -n longhorn-system get \
  nodes.longhorn.io <node-name> -o yaml
```

Check Longhorn workloads on the node:

```bash
kubectl -n longhorn-system get pods -o wide |
  grep '<node-name>'
```

Check:

* Kubelet or RKE2/K3s service
* Container runtime
* Network connectivity
* Longhorn Manager
* Instance Manager
* Disk mounts
* Node conditions and pressure

### Decision

* **Kubernetes reports `NotReady`:** Troubleshoot the node and Kubernetes
  service.
* **Kubernetes is ready but Longhorn is not:** Check Longhorn Manager,
  Instance Manager, disk state, and Longhorn node conditions.
* **The node is permanently unavailable:** Verify replica redundancy before
  removing or replacing it.

---

## LonghornDiskNotReady

### Objective

Restore access to the Longhorn disk path.

### Checks

Inspect Longhorn disk conditions:

```bash
kubectl -n longhorn-system get \
  nodes.longhorn.io <node-name> -o yaml
```

On the node:

```bash
lsblk -f
findmnt
df -h
df -i
```

Check the configured disk path:

```bash
stat <longhorn-disk-path>
findmnt <longhorn-disk-path>
```

Check kernel logs:

```bash
journalctl -k --since "1 hour ago" |
  grep -Ei \
  'I/O error|read-only|filesystem|ext4|xfs|nvme|scsi|blk|reset|timeout'
```

### Decision

* **Mount is missing:** Restore the correct device and mount before allowing
  scheduling.
* **Filesystem is read-only or damaged:** Investigate the device and
  filesystem.
* **Path or permissions changed:** Restore the expected configuration.
* **Disk is permanently failed:** Preserve healthy replicas and replace the
  storage through supported procedures.

---

## LonghornDiskSpaceLow

### Objective

Prevent the disk from reaching the critical threshold.

### Checks

Query remaining usable ratio:

```promql
(
  longhorn_disk_capacity_bytes
  -
  longhorn_disk_usage_bytes
  -
  longhorn_disk_reservation_bytes
)
/
longhorn_disk_capacity_bytes
```

Check node filesystem usage:

```bash
df -h <longhorn-disk-path>
df -i <longhorn-disk-path>
```

Inspect Longhorn disk and replica placement:

```bash
kubectl -n longhorn-system get \
  nodes.longhorn.io <node-name> -o yaml
```

Review:

* Large volumes
* Snapshot accumulation
* Recent rebuilds
* Replica count
* Disk reservation
* Unexpected workload growth

### Actions

* Add storage before capacity becomes critical.
* Add another Longhorn disk or storage node.
* Remove confirmed unused snapshots or volumes through Longhorn.
* Correct unexpected workload data growth.
* Review whether the storage reservation is appropriate.

> [!NOTE]
> With the current alert expressions, this warning and
> `LonghornDiskSpaceCritical` both fire below 5% remaining capacity.

---

## LonghornDiskSpaceCritical

### Objective

Restore usable capacity before replica scheduling and recovery are blocked.

### Immediate Actions

1. Stop nonessential growth where possible.
2. Determine whether active rebuilds require additional space.
3. Add usable capacity or safely remove confirmed obsolete data.
4. Do not manually delete Longhorn replica files.

### Checks

Use the same checks as
[LonghornDiskSpaceLow](#longhorndiskspacelow).

Additionally, identify whether:

* Replica rebuilding is blocked.
* Volumes are degraded.
* The disk has become unschedulable.
* Other disks have enough space for recovery.
* Filesystem inode exhaustion is contributing.

### Actions

* Expand or add storage through supported infrastructure procedures.
* Add another eligible Longhorn disk.
* Remove obsolete snapshots using Longhorn.
* Remove unused volumes only after confirming they are not required.
* Confirm restored capacity in both `df` and Longhorn metrics.

---

## LonghornDiskUnhealthy

### Objective

Determine whether the disk can be restored or must be replaced.

### Checks

Inspect the Longhorn node resource:

```bash
kubectl -n longhorn-system get \
  nodes.longhorn.io <node-name> -o yaml
```

On the node:

```bash
lsblk -f
findmnt
df -h
```

Review kernel errors:

```bash
journalctl -k --since "1 hour ago" |
  grep -Ei \
  'I/O error|medium error|read-only|filesystem|nvme|scsi|blk|reset|timeout'
```

Identify replicas on the affected disk.

Confirm whether affected volumes retain healthy replicas elsewhere.

### Decision

* **Transient mount or connectivity failure:** Restore access and confirm disk
  health.
* **Filesystem failure:** Repair only through an approved maintenance
  procedure.
* **Physical or virtual disk failure:** Replace the storage and rebuild
  replicas elsewhere.
* **Potentially last healthy replica exists on the disk:** Preserve it and
  escalate before changing the disk configuration.

---

# Monitoring Alert Procedures

## LonghornManagerMetricsMissing

### Objective

Restore Prometheus scraping of Longhorn Manager metrics.

### Limitation

The alert uses:

```promql
absent(longhorn_manager_cpu_usage_millicpu)
```

It detects complete absence of the metric across the query scope.

It does not detect one missing Longhorn Manager target when another target
continues exporting the metric.

### Checks

Check Longhorn Manager pods:

```bash
kubectl -n longhorn-system get pods \
  -l app=longhorn-manager \
  -o wide
```

Check services:

```bash
kubectl -n longhorn-system get service
```

Check ServiceMonitor resources:

```bash
kubectl get servicemonitor -A |
  grep -i longhorn
```

Inspect the ServiceMonitor:

```bash
kubectl -n <servicemonitor-namespace> get \
  servicemonitor <servicemonitor-name> -o yaml
```

Check Prometheus targets and search for Longhorn.

Query the metric:

```promql
longhorn_manager_cpu_usage_millicpu
```

Test the endpoint directly:

```bash
LONGHORN_MANAGER_POD="$(
  kubectl -n longhorn-system get pod \
    -l app=longhorn-manager \
    -o jsonpath='{.items[0].metadata.name}'
)"

kubectl -n longhorn-system port-forward \
  "pod/${LONGHORN_MANAGER_POD}" 9500:9500
```

From another terminal:

```bash
curl --fail --silent http://127.0.0.1:9500/metrics |
  grep '^longhorn_manager_cpu_usage_millicpu'
```

### Decision

* **Metric exists at the pod but not Prometheus:** Check ServiceMonitor
  discovery, labels, selectors, namespace selectors, and NetworkPolicy.
* **Metric endpoint is unavailable:** Check Longhorn Manager health and logs.
* **Only some manager targets are missing:** Investigate target-specific scrape
  failures even though the global alert may not fire.
* **Metric name is absent in the installed version:** Validate compatibility
  with the deployed Longhorn release.

---

# Safe Remediation Boundaries

## Generally Safe Actions

After collecting logs and confirming impact, the following actions are usually
low risk:

* Restore a missing Longhorn disk mount.
* Restore node network connectivity.
* Correct insufficient disk capacity.
* Restore failed Kubernetes or Longhorn services.
* Correct Prometheus ServiceMonitor selectors.
* Allow an active replica rebuild to complete.
* Stop unnecessary workload writes during a storage incident.
* Add new storage capacity.

## Actions Requiring Extra Caution

Do not perform these actions without understanding replica and volume state:

* Deleting a Longhorn replica
* Deleting a Longhorn volume
* Removing a Longhorn disk
* Removing a Longhorn node
* Forcing volume detach
* Selecting a replica for faulted-volume recovery
* Running filesystem repair
* Deleting files from the Longhorn disk path
* Restarting every Longhorn Manager or Instance Manager simultaneously
* Restarting multiple storage nodes simultaneously

## Data Preservation Rule

Before a destructive change, collect at minimum:

```bash
kubectl -n longhorn-system get \
  volumes.longhorn.io <volume-name> -o yaml \
  > volume.yaml
```

```bash
kubectl -n longhorn-system get replicas.longhorn.io -o yaml \
  > replicas.yaml
```

```bash
kubectl -n longhorn-system get engines.longhorn.io -o yaml \
  > engines.yaml
```

```bash
kubectl -n longhorn-system get nodes.longhorn.io -o yaml \
  > longhorn-nodes.yaml
```

```bash
kubectl -n longhorn-system get events \
  --sort-by='.lastTimestamp' \
  > longhorn-events.txt
```

---

# Escalation Data

Collect the following when the issue cannot be resolved safely.

## Environment Information

```bash
kubectl version
kubectl get nodes -o wide
kubectl -n longhorn-system get pods -o wide
```

Record:

* Rancher version
* Kubernetes distribution and version
* Longhorn or SUSE Storage version
* Operating system and kernel version
* Filesystem used by Longhorn disks
* Number of storage nodes
* Replica count
* Approximate volume size
* Time the issue began
* Recent maintenance, reboot, upgrade, or infrastructure changes

## Longhorn Resources

```bash
kubectl -n longhorn-system get volumes.longhorn.io -o yaml \
  > volumes.yaml
```

```bash
kubectl -n longhorn-system get engines.longhorn.io -o yaml \
  > engines.yaml
```

```bash
kubectl -n longhorn-system get replicas.longhorn.io -o yaml \
  > replicas.yaml
```

```bash
kubectl -n longhorn-system get nodes.longhorn.io -o yaml \
  > longhorn-nodes.yaml
```

## Kubernetes Resources

```bash
kubectl get pv -o yaml > persistent-volumes.yaml
```

```bash
kubectl get volumeattachments.storage.k8s.io -o yaml \
  > volumeattachments.yaml
```

```bash
kubectl get events -A \
  --sort-by='.lastTimestamp' \
  > cluster-events.txt
```

## Logs

Collect:

* Longhorn Manager logs
* Instance Manager logs
* CSI plugin logs
* Workload logs
* Kubelet or RKE2/K3s logs
* Kernel logs
* Prometheus target and rule information for monitoring incidents

## Longhorn Support Bundle

Generate a Longhorn support bundle from the Longhorn UI when available.

Record:

* Bundle generation time
* Affected volume
* Affected nodes
* Alert start time
* Timezone used during investigation

---

# Recovery Validation

Do not consider the incident resolved only because the alert disappeared.

## Verify Volume Health

```bash
kubectl -n longhorn-system get volumes.longhorn.io
```

Confirm:

* Expected volume state
* Expected robustness
* Correct attachment node
* No recurring engine or replica errors

## Verify Replica Redundancy

```bash
kubectl -n longhorn-system get replicas.longhorn.io -o wide
```

Confirm:

* Expected number of healthy replicas
* No replica remains in `error` or `unknown`
* Rebuilds completed successfully
* Replicas are distributed according to the intended policy

## Verify Node and Disk Health

```bash
kubectl get nodes
```

```bash
kubectl -n longhorn-system get nodes.longhorn.io
```

Confirm:

* Kubernetes nodes are ready.
* Longhorn nodes are ready.
* Longhorn disks are ready and healthy.
* Sufficient usable capacity remains.

## Verify Workload Access

Confirm that the application can:

* Mount the PVC
* Read existing data
* Write new data
* Restart successfully
* Complete application-specific health checks

Review recent workload logs for I/O errors.

## Verify Monitoring

Confirm that Longhorn metrics are available:

```promql
longhorn_manager_cpu_usage_millicpu
```

Confirm that no Longhorn alerts remain active unexpectedly:

```promql
ALERTS{
  alertstate="firing",
  component="longhorn"
}
```

## Observe After Recovery

Continue monitoring for recurrence, especially after:

* Node recovery
* Disk replacement
* Replica rebuilding
* Volume expansion
* Filesystem repair
* Prometheus scrape restoration

---

# Related Documentation

* [Alert Reference](alert-reference.md)
* [Metric Validation](metric-validation.md)
* [Project README](../README.md)
