# Longhorn Health Monitor Alert Reference

## Overview

This document describes the alerts included with the Longhorn Health Monitor.

Each alert section includes:

* Severity and category
* Alert condition
* Operational impact
* Common causes
* Investigation steps
* Recommended actions

> [!IMPORTANT]
> Alert thresholds should be reviewed and adjusted for the Longhorn version,
> storage architecture, workload requirements, and operational procedures of
> each environment.

## Table of Contents

### Volume Health

* [LonghornVolumeDegraded](#longhornvolumedegraded)
* [LonghornVolumeFaulted](#longhornvolumefaulted)
* [LonghornVolumeRobustnessUnknown](#longhornvolumerobustnessunknown)
* [LonghornVolumeFilesystemReadOnly](#longhornvolumefilesystemreadonly)
* [LonghornVolumeActualSpaceHigh](#longhornvolumeactualspacehigh)

### Replica and Engine Health

* [LonghornReplicaError](#longhornreplicaerror)
* [LonghornReplicaUnknown](#longhornreplicaunknown)
* [LonghornEngineError](#longhornengineerror)
* [LonghornEngineUnknown](#longhornengineunknown)
* [LonghornEngineReplicaModeError](#longhornenginereplicamodeerror)
* [LonghornReplicaRebuildStalled](#longhornreplicarebuildstalled)

### Node and Disk Health

* [LonghornNodeNotReady](#longhornnodenotready)
* [LonghornDiskNotReady](#longhorndisknotready)
* [LonghornDiskSpaceLow](#longhorndiskspacelow)
* [LonghornDiskSpaceCritical](#longhorndiskspacecritical)
* [LonghornDiskUnhealthy](#longhorndiskunhealthy)

### Monitoring Health

* [LonghornManagerMetricsMissing](#longhornmanagermetricsmissing)

---

## Common Investigation Commands

### Check Longhorn workloads

```bash
kubectl -n longhorn-system get pods -o wide
```

### Check Longhorn custom resources

```bash
kubectl -n longhorn-system get \
  volumes.longhorn.io,\
engines.longhorn.io,\
replicas.longhorn.io
```

### Check Longhorn nodes

```bash
kubectl -n longhorn-system get nodes.longhorn.io
```

### Check Kubernetes node status

```bash
kubectl get nodes -o wide
```

### Review Longhorn Manager logs

```bash
kubectl -n longhorn-system logs \
  -l app=longhorn-manager \
  --prefix \
  --tail=200
```

### Review Longhorn events

```bash
kubectl -n longhorn-system get events \
  --sort-by='.lastTimestamp'
```

### Inspect a specific volume

Replace `<volume-name>` with the affected Longhorn volume.

```bash
kubectl -n longhorn-system describe \
  volumes.longhorn.io <volume-name>
```

### Inspect replicas for a volume

Replace `<volume-name>` with the affected Longhorn volume.

```bash
kubectl -n longhorn-system get replicas.longhorn.io \
  -l longhornvolume=<volume-name> \
  -o wide
```

### Inspect engines for a volume

Replace `<volume-name>` with the affected Longhorn volume.

```bash
kubectl -n longhorn-system get engines.longhorn.io \
  -l longhornvolume=<volume-name> \
  -o wide
```

> [!NOTE]
> Available labels can differ between Longhorn versions. When a label-based
> command returns no results, list all resources and filter by the volume name.

```bash
kubectl -n longhorn-system get replicas.longhorn.io -o wide
kubectl -n longhorn-system get engines.longhorn.io -o wide
```

---

# Volume Health Alerts

## LonghornVolumeDegraded

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `warning`  |
| Category          | `volume`   |
| Evaluation period | `10m`      |
| Component         | `longhorn` |

### Condition

```promql
longhorn_volume_robustness{state="degraded"} == 1
```

### Meaning

A Longhorn volume has remained in a degraded state for more than 10 minutes.

The volume may remain accessible, but one or more replicas are unavailable,
failed, or rebuilding. The volume therefore has less redundancy than intended.

### Impact

* Reduced storage fault tolerance
* Increased risk if another replica, disk, or node fails
* Potentially reduced performance during replica rebuilding
* Possible application disruption if additional failures occur

### Common Causes

* A Longhorn node rebooted or became unavailable.
* A replica process failed.
* A replica is being rebuilt.
* A disk became unavailable or unschedulable.
* Network connectivity between Longhorn components was interrupted.
* Longhorn could not schedule a replacement replica.
* The cluster does not have sufficient free storage for another replica.

### Investigation

1. Identify degraded volumes:

   ```bash
   kubectl -n longhorn-system get volumes.longhorn.io
   ```

2. Inspect the affected volume:

   ```bash
   kubectl -n longhorn-system describe \
     volumes.longhorn.io <volume-name>
   ```

3. Review replicas associated with the volume:

   ```bash
   kubectl -n longhorn-system get replicas.longhorn.io -o wide
   ```

4. Check whether a rebuild is in progress:

   ```promql
   longhorn_engine_rebuild_progress
   ```

5. Check Longhorn and Kubernetes node health:

   ```bash
   kubectl get nodes -o wide
   kubectl -n longhorn-system get nodes.longhorn.io
   ```

6. Review Longhorn Manager logs:

   ```bash
   kubectl -n longhorn-system logs \
     -l app=longhorn-manager \
     --prefix \
     --since=30m
   ```

### Recommended Actions

* Restore connectivity to an unavailable node.
* Resolve disk or filesystem problems on the affected node.
* Confirm that sufficient usable storage exists for replica rebuilding.
* Allow an active replica rebuild to complete.
* Correct replica scheduling constraints when Longhorn cannot create a
  replacement replica.
* Investigate recurring degradation before manually deleting or recreating
  replicas.

### Escalation Guidance

Collect the following before escalation:

```bash
kubectl -n longhorn-system get volumes.longhorn.io <volume-name> -o yaml
kubectl -n longhorn-system get replicas.longhorn.io -o yaml
kubectl -n longhorn-system get engines.longhorn.io -o yaml
kubectl -n longhorn-system get nodes.longhorn.io -o yaml
kubectl -n longhorn-system get events --sort-by='.lastTimestamp'
```

---

## LonghornVolumeFaulted

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `critical` |
| Category          | `volume`   |
| Evaluation period | `2m`       |
| Component         | `longhorn` |

### Condition

```promql
longhorn_volume_robustness{state="faulted"} == 1
```

### Meaning

A Longhorn volume has remained faulted for more than two minutes.

A faulted volume may no longer have a healthy replica that can provide the
required data. Workloads using the associated PVC may be unable to read or
write storage.

### Impact

* Application outage
* PVC mount or I/O failures
* Volume unavailability
* Potential data-loss risk
* Manual recovery may be required

### Common Causes

* All usable replicas became unavailable.
* Multiple replica-hosting nodes failed.
* Multiple Longhorn disks became unavailable.
* Engine or replica processes failed.
* Storage or filesystem corruption occurred.
* Network failures isolated the engine from every replica.

### Investigation

1. Identify the faulted volume and associated PVC:

   ```bash
   kubectl -n longhorn-system get volumes.longhorn.io
   ```

2. Inspect the volume:

   ```bash
   kubectl -n longhorn-system describe \
     volumes.longhorn.io <volume-name>
   ```

3. Inspect the replicas and determine whether any contain usable data:

   ```bash
   kubectl -n longhorn-system get replicas.longhorn.io -o wide
   ```

4. Inspect the engine:

   ```bash
   kubectl -n longhorn-system get engines.longhorn.io -o wide
   ```

5. Check the health of replica-hosting nodes:

   ```bash
   kubectl get nodes -o wide
   ```

6. Review recent Longhorn events and logs:

   ```bash
   kubectl -n longhorn-system get events \
     --sort-by='.lastTimestamp'

   kubectl -n longhorn-system logs \
     -l app=longhorn-manager \
     --prefix \
     --since=30m
   ```

7. Check whether a usable backup exists before taking destructive recovery
   actions.

### Recommended Actions

* Restore unavailable nodes before attempting replica recovery.
* Restore access to affected Longhorn disks.
* Confirm which replica contains the most recent usable data.
* Follow the documented Longhorn volume recovery procedure.
* Restore the volume from backup when healthy replicas cannot be recovered.
* Avoid deleting replicas until their state and recovery value are understood.

> [!CAUTION]
> Selecting or reusing an incorrect replica during recovery can result in data
> loss. Preserve the affected resources and collect support data before making
> destructive changes.

---

## LonghornVolumeRobustnessUnknown

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `warning`  |
| Category          | `volume`   |
| Evaluation period | `10m`      |
| Component         | `longhorn` |

### Condition

```promql
longhorn_volume_robustness{state="unknown"} == 1
```

### Meaning

Longhorn has been unable to determine the robustness of a volume for more than
10 minutes.

An unknown state may indicate that Longhorn cannot obtain sufficient
information from the volume, engine, replicas, or manager components.

### Impact

* Volume health cannot be reliably determined.
* Storage failures may not be reflected accurately.
* The volume may be transitioning between states.
* Monitoring visibility for the volume is incomplete.

### Common Causes

* The volume or engine is still initializing.
* Longhorn Manager cannot communicate with instance-manager components.
* Engine or replica status information is unavailable.
* A node or network interruption occurred.
* A Longhorn component is restarting or unhealthy.
* Metrics are stale or incomplete.

### Investigation

1. Check the volume state:

   ```bash
   kubectl -n longhorn-system get volumes.longhorn.io <volume-name> -o yaml
   ```

2. Check the engine and replicas:

   ```bash
   kubectl -n longhorn-system get engines.longhorn.io -o wide
   kubectl -n longhorn-system get replicas.longhorn.io -o wide
   ```

3. Check Longhorn workloads:

   ```bash
   kubectl -n longhorn-system get pods -o wide
   ```

4. Check for restarting or unavailable instance-manager pods:

   ```bash
   kubectl -n longhorn-system get pods \
     -l longhorn.io/component=instance-manager \
     -o wide
   ```

5. Review recent events and Longhorn Manager logs.

### Recommended Actions

* Restore unhealthy Longhorn workloads.
* Resolve node or network connectivity issues.
* Wait for a recently attached or recovering volume to stabilize.
* Investigate persistent engine or replica status failures.
* Verify that Prometheus is receiving current Longhorn metrics.

---

## LonghornVolumeFilesystemReadOnly

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `critical` |
| Category          | `volume`   |
| Evaluation period | `5m`       |
| Component         | `longhorn` |

### Condition

```promql
longhorn_volume_file_system_read_only == 1
```

### Meaning

The filesystem associated with a Longhorn volume has been detected as
read-only for more than five minutes.

The filesystem may have been remounted read-only by the operating system after
detecting storage, filesystem, or I/O errors.

### Impact

* Applications may be unable to write data.
* Database or application consistency may be affected.
* Pods may report I/O or permission-like errors.
* Application availability may be degraded.
* Filesystem repair may be required.

### Common Causes

* Filesystem corruption
* Storage I/O errors
* Node or kernel storage errors
* Unexpected node shutdown
* Underlying disk failure
* Longhorn engine or replica instability
* Filesystem protection behavior after detected errors

### Investigation

1. Identify the volume, PVC, namespace, workload, and node from the alert
   labels.

2. Check the affected workload:

   ```bash
   kubectl -n <workload-namespace> get pods -o wide
   ```

3. Review workload logs:

   ```bash
   kubectl -n <workload-namespace> logs <pod-name>
   ```

4. Review Kubernetes events:

   ```bash
   kubectl -n <workload-namespace> get events \
     --sort-by='.lastTimestamp'
   ```

5. Inspect the Longhorn volume:

   ```bash
   kubectl -n longhorn-system get \
     volumes.longhorn.io <volume-name> -o yaml
   ```

6. Review kernel logs on the node hosting the workload:

   ```bash
   journalctl -k --since "1 hour ago"
   ```

7. Search for filesystem and block-device errors:

   ```bash
   journalctl -k --since "1 hour ago" |
     grep -Ei 'I/O error|read-only|filesystem|ext4|xfs|blk|scsi|nvme'
   ```

8. Confirm whether the filesystem is mounted read-only inside the workload or
   on the node.

### Recommended Actions

* Stop or scale down applications that continue attempting writes.
* Preserve application and node logs.
* Determine whether the problem is caused by the filesystem, node, or
  Longhorn storage layer.
* Follow the filesystem-specific repair procedure during an approved
  maintenance window.
* Restore from backup if filesystem repair cannot safely recover the data.
* Investigate the underlying cause before returning the workload to service.

> [!CAUTION]
> Do not run filesystem repair against a mounted filesystem. Confirm the
> filesystem type, detach the volume when required, and follow an approved
> recovery procedure.

---

## LonghornVolumeActualSpaceHigh

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `warning`  |
| Category          | `volume`   |
| Evaluation period | `15m`      |
| Component         | `longhorn` |

### Condition

```promql
(
  longhorn_volume_actual_size_bytes
  /
  longhorn_volume_capacity_bytes
) > 0.90
```

### Meaning

Longhorn reports that a volume's actual size is greater than 90% of its
configured capacity for more than 15 minutes.

Longhorn actual size and filesystem usage inside the workload are related but
may not be identical. Snapshots, removed data, filesystem behavior, and storage
allocation can affect the value reported by Longhorn.

### Impact

* The volume is approaching its configured capacity.
* Additional writes may eventually fail.
* Snapshot and replica operations may require additional storage.
* Replica rebuilds can place additional pressure on node storage.

### Common Causes

* Normal workload data growth
* Unremoved application data
* Accumulated Longhorn snapshots
* Filesystem blocks not immediately reclaimed
* Insufficient initial volume capacity
* Unexpected application log or database growth

### Investigation

1. Compare Longhorn actual size with configured capacity:

   ```promql
   longhorn_volume_actual_size_bytes
   /
   longhorn_volume_capacity_bytes
   ```

2. Check the volume configuration:

   ```bash
   kubectl -n longhorn-system get \
     volumes.longhorn.io <volume-name> -o yaml
   ```

3. Check PVC capacity:

   ```bash
   kubectl -n <pvc-namespace> get pvc <pvc-name>
   ```

4. Check filesystem usage from the workload when possible:

   ```bash
   df -h
   ```

5. Review the volume's Longhorn snapshots.

6. Check the usable capacity of disks that host the volume's replicas.

### Recommended Actions

* Remove unnecessary application data.
* Configure application log retention.
* Remove obsolete Longhorn snapshots after verifying they are not required.
* Expand the PVC and Longhorn volume when supported and appropriate.
* Confirm that replica-hosting disks have enough capacity for the expanded
  replicas.
* Continue monitoring after cleanup or expansion.

---

# Replica and Engine Health Alerts

## LonghornReplicaError

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `critical` |
| Category          | `replica`  |
| Evaluation period | `5m`       |
| Component         | `longhorn` |

### Condition

```promql
longhorn_replica_state{state="error"} == 1
```

### Meaning

A Longhorn replica has remained in an error state for more than five minutes.

The affected volume may still be available through other healthy replicas, but
its redundancy may be reduced.

### Impact

* Reduced volume redundancy
* Increased data-loss risk if additional replicas fail
* Possible volume degradation
* A replacement replica may need to be rebuilt

### Common Causes

* Replica process failure
* Disk failure or unavailability
* Node failure
* Network interruption
* Instance-manager failure
* Storage I/O errors
* Replica data corruption

### Investigation

1. Inspect the replica:

   ```bash
   kubectl -n longhorn-system get \
     replicas.longhorn.io <replica-name> -o yaml
   ```

2. Inspect the associated volume:

   ```bash
   kubectl -n longhorn-system get \
     volumes.longhorn.io <volume-name> -o yaml
   ```

3. Check the replica-hosting node and disk:

   ```bash
   kubectl get node <node-name>
   kubectl -n longhorn-system get \
     nodes.longhorn.io <node-name> -o yaml
   ```

4. Review instance-manager and Longhorn Manager logs.

5. Check for disk, filesystem, and kernel I/O errors on the node.

### Recommended Actions

* Restore the affected node or disk.
* Resolve instance-manager or network failures.
* Verify that other replicas are healthy before removing the failed replica.
* Allow Longhorn to rebuild a replacement replica when sufficient storage is
  available.
* Investigate repeated replica failures on the same node or disk.

---

## LonghornReplicaUnknown

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `warning`  |
| Category          | `replica`  |
| Evaluation period | `10m`      |
| Component         | `longhorn` |

### Condition

```promql
longhorn_replica_state{state="unknown"} == 1
```

### Meaning

A Longhorn replica has reported an unknown state for more than 10 minutes.

Longhorn may be unable to communicate with the replica process or determine
its current state.

### Impact

* Replica health cannot be confirmed.
* Volume redundancy may be lower than expected.
* A volume may become degraded.
* Replica recovery or rebuilding may be delayed.

### Common Causes

* Instance-manager communication failure
* Replica process restart
* Node or network interruption
* Stale replica status
* Longhorn Manager restart
* An incomplete attach, detach, or recovery operation

### Investigation

1. Inspect the replica resource:

   ```bash
   kubectl -n longhorn-system get \
     replicas.longhorn.io <replica-name> -o yaml
   ```

2. Check the replica-hosting node:

   ```bash
   kubectl get node <node-name>
   ```

3. Check Longhorn workloads on the node:

   ```bash
   kubectl -n longhorn-system get pods -o wide |
     grep '<node-name>'
   ```

4. Review instance-manager and Longhorn Manager logs.

5. Inspect the associated engine and volume state.

### Recommended Actions

* Restore connectivity to the replica-hosting node.
* Recover unhealthy instance-manager components.
* Allow temporary transitional states to stabilize.
* Investigate replicas that remain unknown after the node and Longhorn
  components are healthy.

---

## LonghornEngineError

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `critical` |
| Category          | `engine`   |
| Evaluation period | `5m`       |
| Component         | `longhorn` |

### Condition

```promql
longhorn_engine_state{state="error"} == 1
```

### Meaning

A Longhorn engine has remained in an error state for more than five minutes.

The engine provides the active data path between a workload and the volume's
replicas. An engine error can therefore affect volume availability.

### Impact

* Volume I/O may fail.
* The associated workload may become unavailable.
* The volume may be unable to attach or remain attached.
* Replica communication may be interrupted.

### Common Causes

* Engine process failure
* Instance-manager failure
* Node resource exhaustion
* Network interruption between engine and replicas
* Replica failures
* Node shutdown or restart
* Storage I/O errors

### Investigation

1. Inspect the engine:

   ```bash
   kubectl -n longhorn-system get \
     engines.longhorn.io <engine-name> -o yaml
   ```

2. Inspect the associated volume and replicas:

   ```bash
   kubectl -n longhorn-system get \
     volumes.longhorn.io <volume-name> -o yaml

   kubectl -n longhorn-system get replicas.longhorn.io -o wide
   ```

3. Check the node hosting the engine:

   ```bash
   kubectl get node <node-name>
   ```

4. Check the instance-manager pod on the node.

5. Review Longhorn Manager and instance-manager logs.

6. Check node resource usage and kernel logs.

### Recommended Actions

* Restore the engine-hosting node.
* Recover the affected instance-manager.
* Resolve communication failures between the engine and replicas.
* Verify replica health before attempting volume recovery.
* Follow documented Longhorn recovery procedures if the engine does not
  recover automatically.

---

## LonghornEngineUnknown

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `warning`  |
| Category          | `engine`   |
| Evaluation period | `10m`      |
| Component         | `longhorn` |

### Condition

```promql
longhorn_engine_state{state="unknown"} == 1
```

### Meaning

A Longhorn engine has reported an unknown state for more than 10 minutes.

Longhorn may be unable to communicate with the engine process or determine its
current state.

### Impact

* Volume availability cannot be confirmed.
* Monitoring information may be incomplete.
* Attach, detach, or recovery operations may be delayed.
* The associated volume may become degraded or unavailable.

### Common Causes

* Engine process initialization or restart
* Instance-manager communication failure
* Node or network interruption
* Longhorn Manager restart
* Stale engine status
* Incomplete volume attachment or detachment

### Investigation

1. Inspect the engine resource:

   ```bash
   kubectl -n longhorn-system get \
     engines.longhorn.io <engine-name> -o yaml
   ```

2. Check the engine-hosting node.

3. Check the associated instance-manager pod.

4. Inspect the volume and replica states.

5. Review Longhorn Manager and instance-manager logs.

### Recommended Actions

* Restore the affected Longhorn components.
* Resolve node or network connectivity issues.
* Allow a temporary engine transition to complete.
* Investigate an engine that remains unknown after all related components are
  healthy.

---

## LonghornEngineReplicaModeError

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `critical` |
| Category          | `replica`  |
| Evaluation period | `5m`       |
| Component         | `longhorn` |

### Condition

```promql
longhorn_engine_replica_mode{mode="ERR"} == 1
```

### Meaning

A Longhorn engine has reported one of its replicas in `ERR` mode for more than
five minutes.

The engine is no longer using the affected replica as a healthy member of the
volume's replica set.

### Impact

* Reduced volume redundancy
* Possible degraded volume state
* Increased risk if another replica fails
* Replica rebuilding may be required

### Common Causes

* Replica process failure
* Communication failure between engine and replica
* Replica-hosting node failure
* Disk I/O errors
* Replica data inconsistency
* Instance-manager failure

### Investigation

1. Identify the engine, volume, replica, and node from the alert labels.

2. Inspect the engine:

   ```bash
   kubectl -n longhorn-system get \
     engines.longhorn.io <engine-name> -o yaml
   ```

3. Inspect the affected replica:

   ```bash
   kubectl -n longhorn-system get \
     replicas.longhorn.io <replica-name> -o yaml
   ```

4. Check the associated node and disk.

5. Review engine and replica instance-manager logs.

6. Check whether Longhorn is already rebuilding a replacement replica.

### Recommended Actions

* Restore communication with the affected replica.
* Resolve node or disk failures.
* Verify the health of the remaining replicas.
* Allow Longhorn to rebuild a replacement replica.
* Do not remove multiple replicas simultaneously.
* Investigate repeated `ERR` mode transitions.

---

## LonghornReplicaRebuildStalled

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `warning`  |
| Category          | `rebuild`  |
| Evaluation period | `30m`      |
| Lookback window   | `30m`      |
| Component         | `longhorn` |

### Condition

```promql
longhorn_engine_rebuild_progress < 100
and
changes(longhorn_engine_rebuild_progress[30m]) == 0
```

### Meaning

A replica rebuild is incomplete, and the reported rebuild progress has not
changed during the preceding 30-minute window.

The rule must then remain true for an additional 30 minutes before the alert
fires.

> [!NOTE]
> Because the expression checks a 30-minute history and also uses `for: 30m`,
> the alert may take approximately one hour to fire after measurable rebuild
> progress stops.

### Impact

* The volume remains at reduced redundancy.
* Recovery from a replica failure is delayed.
* Another failure may place the volume at greater risk.
* Storage and network resources may remain consumed by the stalled rebuild.

### Common Causes

* Slow or failed replica-hosting disk
* Network interruption between rebuild source and destination
* Instance-manager instability
* Insufficient node resources
* Replica process failure
* Engine communication failure
* Rebuild destination node or disk becoming unavailable
* Very low rebuild performance

### Investigation

1. Check the current rebuild progress:

   ```promql
   longhorn_engine_rebuild_progress
   ```

2. Inspect the engine:

   ```bash
   kubectl -n longhorn-system get \
     engines.longhorn.io <engine-name> -o yaml
   ```

3. Inspect the source and destination replicas.

4. Check the source and destination nodes:

   ```bash
   kubectl get nodes -o wide
   ```

5. Check Longhorn disk readiness and available capacity:

   ```bash
   kubectl -n longhorn-system get nodes.longhorn.io -o yaml
   ```

6. Review engine, replica, and Longhorn Manager logs.

7. Check CPU, memory, disk latency, filesystem errors, and network errors on
   both nodes.

### Recommended Actions

* Restore unavailable source or destination nodes.
* Resolve disk I/O or network problems.
* Confirm that the destination disk has enough usable capacity.
* Allow a slow but progressing rebuild to continue.
* Investigate before manually stopping or restarting a rebuild.
* Replace an unusable destination replica only after confirming the remaining
  replica set is healthy.

---

# Node and Disk Health Alerts

## LonghornNodeNotReady

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `critical` |
| Category          | `node`     |
| Evaluation period | `5m`       |
| Component         | `longhorn` |

### Condition

```promql
longhorn_node_status{condition="ready"} == 0
```

### Meaning

A node managed by Longhorn has reported `Ready=false` for more than five
minutes.

This alert reflects Longhorn's view of the node. The Kubernetes Node object may
or may not also report `NotReady`.

### Impact

* Replicas on the node may become unavailable.
* Volumes may become degraded or faulted.
* New replicas may not be scheduled on the node.
* Attached workloads may experience storage disruption.

### Common Causes

* Kubernetes node failure
* Longhorn Manager unavailable on the node
* Network connectivity failure
* Node reboot or shutdown
* Kubelet or container runtime failure
* Disk or mount failure
* Longhorn node configuration problem

### Investigation

1. Compare Kubernetes and Longhorn node status:

   ```bash
   kubectl get node <node-name> -o yaml

   kubectl -n longhorn-system get \
     nodes.longhorn.io <node-name> -o yaml
   ```

2. Check Longhorn workloads on the node:

   ```bash
   kubectl -n longhorn-system get pods -o wide |
     grep '<node-name>'
   ```

3. Check node conditions and events:

   ```bash
   kubectl describe node <node-name>
   ```

4. Review kubelet, container runtime, and kernel logs.

5. Check network connectivity to the Kubernetes API and other Longhorn nodes.

### Recommended Actions

* Restore Kubernetes node health.
* Restart failed node services only after collecting relevant logs.
* Resolve network or filesystem problems.
* Restore Longhorn Manager and instance-manager pods.
* Confirm volume and replica health after the node returns.

---

## LonghornDiskNotReady

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `warning`  |
| Category          | `disk`     |
| Evaluation period | `10m`      |
| Component         | `longhorn` |

### Condition

```promql
longhorn_disk_status{condition="ready"} == 0
```

### Meaning

A disk configured for Longhorn has reported `Ready=false` for more than 10
minutes.

Longhorn may be unable to access, validate, or use the disk.

### Impact

* New replicas cannot be scheduled to the disk.
* Existing replicas may become unavailable.
* Volumes may become degraded.
* Rebuilds may fail or remain pending.
* Storage capacity available to Longhorn is reduced.

### Common Causes

* Disk path is missing or unmounted.
* Filesystem became read-only.
* Underlying block device failed.
* Disk configuration changed.
* Node restart did not restore the mount.
* Permissions or ownership changed.
* Longhorn cannot access the disk path.

### Investigation

1. Inspect the Longhorn node and disk status:

   ```bash
   kubectl -n longhorn-system get \
     nodes.longhorn.io <node-name> -o yaml
   ```

2. Verify the disk path exists on the node:

   ```bash
   findmnt
   df -h
   ```

3. Check whether the expected device is mounted:

   ```bash
   lsblk -f
   ```

4. Review kernel and filesystem logs:

   ```bash
   journalctl -k --since "1 hour ago"
   ```

5. Check disk path permissions and available space.

6. Review Longhorn Manager logs on the affected node.

### Recommended Actions

* Restore the missing disk mount.
* Correct the Longhorn disk path when configuration is incorrect.
* Resolve filesystem or block-device failures.
* Restore required permissions.
* Replace failed storage.
* Confirm that existing replicas are healthy before deleting or reconfiguring
  the disk.

---

## LonghornDiskSpaceLow

| Field             | Value                           |
| ----------------- | ------------------------------- |
| Severity          | `warning`                       |
| Category          | `capacity`                      |
| Evaluation period | `15m`                           |
| Threshold         | Less than `15%` usable capacity |
| Component         | `longhorn`                      |

### Condition

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
< 0.15
```

### Meaning

A Longhorn disk has less than 15% usable capacity remaining after accounting
for used and reserved storage.

### Impact

* Replica scheduling may become constrained.
* Replica rebuilding may fail.
* Volume expansion may fail.
* Longhorn may mark the disk unschedulable.
* Continued growth may trigger the critical capacity alert.

### Common Causes

* Normal volume growth
* Accumulated snapshots
* Increased replica count
* Failed replica rebuilds leaving data behind
* Insufficient storage capacity
* High disk reservation
* Unexpected application data growth

### Investigation

1. Check Longhorn disk capacity metrics:

   ```promql
   longhorn_disk_capacity_bytes
   -
   longhorn_disk_usage_bytes
   -
   longhorn_disk_reservation_bytes
   ```

2. Inspect disk configuration:

   ```bash
   kubectl -n longhorn-system get \
     nodes.longhorn.io <node-name> -o yaml
   ```

3. Check filesystem capacity on the node:

   ```bash
   df -h
   ```

4. Review volumes and replicas using the disk.

5. Review snapshot usage and recent workload growth.

### Recommended Actions

* Add storage capacity.
* Add another Longhorn disk or storage node.
* Remove unused volumes and snapshots after validation.
* Adjust storage reservation only when operational requirements permit.
* Move workloads or replicas through supported Longhorn procedures.
* Investigate unexpected growth before the disk reaches the critical
  threshold.

> [!NOTE]
> With the current rules, both `LonghornDiskSpaceLow` and
> `LonghornDiskSpaceCritical` can fire when usable capacity falls below 5%.
> Alertmanager inhibition or mutually exclusive warning and critical
> expressions can be used to prevent duplicate notifications.

---

## LonghornDiskSpaceCritical

| Field             | Value                          |
| ----------------- | ------------------------------ |
| Severity          | `critical`                     |
| Category          | `capacity`                     |
| Evaluation period | `5m`                           |
| Threshold         | Less than `5%` usable capacity |
| Component         | `longhorn`                     |

### Condition

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
< 0.05
```

### Meaning

A Longhorn disk has less than 5% usable capacity remaining after accounting for
used and reserved storage.

### Impact

* Replica scheduling may fail.
* Replica rebuilds may be blocked.
* Volume expansion may fail.
* Existing workloads may be at increased operational risk.
* Longhorn may stop scheduling additional replica data to the disk.

### Common Causes

* Uncontrolled workload data growth
* Excessive snapshots
* Insufficient storage capacity
* Multiple large replicas on the same disk
* Failed cleanup or retention processes
* Incorrectly sized disk reservation

### Investigation

1. Verify the available Longhorn and filesystem capacity.

2. Identify volumes and replicas consuming the disk.

3. Check for unexpected snapshot or application data growth.

4. Confirm whether active rebuilds are consuming additional space.

5. Review other Longhorn disks to determine whether sufficient capacity exists
   elsewhere.

### Recommended Actions

* Add usable storage capacity immediately.
* Reduce application data growth where possible.
* Remove confirmed obsolete snapshots or volumes.
* Expand the underlying storage only through a supported procedure.
* Avoid deleting replica data directly from the filesystem.
* Confirm that enough capacity exists for ongoing rebuild and recovery
  operations.

> [!CAUTION]
> Do not manually delete files from a Longhorn disk path. Longhorn manages the
> contents of that path, and manual removal can cause volume corruption or data
> loss.

---

## LonghornDiskUnhealthy

| Field             | Value      |
| ----------------- | ---------- |
| Severity          | `critical` |
| Category          | `disk`     |
| Evaluation period | `5m`       |
| Component         | `longhorn` |

### Condition

```promql
longhorn_disk_health == 0
```

### Meaning

A Longhorn disk is reporting an unhealthy status.

The disk may no longer be safe or available for storing replica data.

### Impact

* Replicas on the disk may become unavailable.
* Volumes may become degraded or faulted.
* New replicas may not be scheduled.
* Replica rebuilds may be required.
* Data-loss risk increases if additional replicas fail.

### Common Causes

* Physical or virtual disk failure
* Filesystem errors
* Read-only filesystem
* Missing mount
* Severe I/O latency or timeout
* Device disconnection
* Storage path corruption

### Investigation

1. Inspect the affected Longhorn disk:

   ```bash
   kubectl -n longhorn-system get \
     nodes.longhorn.io <node-name> -o yaml
   ```

2. Check the device and filesystem:

   ```bash
   lsblk -f
   findmnt
   df -h
   ```

3. Review kernel errors:

   ```bash
   journalctl -k --since "1 hour ago" |
     grep -Ei 'I/O error|timeout|reset|read-only|filesystem|scsi|nvme|blk'
   ```

4. Identify replicas located on the disk.

5. Determine whether affected volumes still have healthy replicas elsewhere.

### Recommended Actions

* Restore the device or mount when the issue is temporary.
* Replace failed storage.
* Allow Longhorn to rebuild replicas on healthy disks.
* Disable scheduling to the disk until its health is confirmed.
* Preserve healthy replicas before removing an unhealthy disk.
* Investigate repeated disk-health failures at the infrastructure layer.

---

# Monitoring Health Alerts

## LonghornManagerMetricsMissing

| Field             | Value        |
| ----------------- | ------------ |
| Severity          | `critical`   |
| Category          | `monitoring` |
| Evaluation period | `10m`        |
| Component         | `longhorn`   |

### Condition

```promql
absent(longhorn_manager_cpu_usage_millicpu)
```

### Meaning

Prometheus has not received the
`longhorn_manager_cpu_usage_millicpu` metric from any Longhorn Manager target
for more than 10 minutes.

This alert indicates a loss of Longhorn monitoring visibility. It does not
necessarily mean that the Longhorn storage system itself is unavailable.

### Impact

* Longhorn alerts may stop evaluating correctly.
* Storage degradation may go undetected.
* Grafana dashboard panels may show no data.
* Monitoring cannot reliably report Longhorn health.

### Common Causes

* Longhorn Manager pods are unavailable.
* Prometheus cannot scrape the Longhorn metrics endpoint.
* The ServiceMonitor is missing or misconfigured.
* Prometheus selectors do not match the ServiceMonitor.
* NetworkPolicy rules block scraping.
* The Longhorn metrics service is unavailable.
* Longhorn metric names differ in the installed version.

### Investigation

1. Check Longhorn Manager pods:

   ```bash
   kubectl -n longhorn-system get pods \
     -l app=longhorn-manager \
     -o wide
   ```

2. Check the Longhorn Manager service:

   ```bash
   kubectl -n longhorn-system get service
   ```

3. Check ServiceMonitor resources:

   ```bash
   kubectl get servicemonitor -A |
     grep -i longhorn
   ```

4. Inspect the matching ServiceMonitor:

   ```bash
   kubectl -n <namespace> get \
     servicemonitor <servicemonitor-name> -o yaml
   ```

5. Check Prometheus targets in the Prometheus UI.

6. Query the metric directly:

   ```promql
   longhorn_manager_cpu_usage_millicpu
   ```

7. Test a Longhorn Manager metrics endpoint:

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

8. Check Prometheus and Prometheus Operator logs when the target is not
   discovered.

### Recommended Actions

* Restore unavailable Longhorn Manager pods.
* Correct the ServiceMonitor namespace, selectors, labels, or endpoints.
* Confirm that Rancher Monitoring selects the Longhorn ServiceMonitor.
* Correct NetworkPolicy or firewall restrictions.
* Verify the metric name against the installed Longhorn version.
* Restore metric collection before relying on the Longhorn Health Monitor.

### Important Limitation

The `absent()` expression detects the complete absence of this metric across
the query scope.

It does not identify a single missing Longhorn Manager target when another
manager continues exposing the same metric. Per-target scrape monitoring should
be added separately when the Prometheus target labels used by the environment
are known.

---

# Severity Definitions

| Severity   | Description                                                                                         | Expected Response                                                          |
| ---------- | --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `warning`  | A degraded or potentially unsafe condition exists. The affected component may still be operational. | Investigate promptly and correct the condition before it becomes critical. |
| `critical` | Availability, data integrity, recovery capability, or monitoring coverage may be at immediate risk. | Begin investigation and remediation immediately.                           |

---

# Alert Summary

| Alert                              | Severity | Category   | Evaluation period                                                     |
| ---------------------------------- | -------- | ---------- | --------------------------------------------------------------------- |
| `LonghornVolumeDegraded`           | Warning  | Volume     | 10 minutes                                                            |
| `LonghornVolumeFaulted`            | Critical | Volume     | 2 minutes                                                             |
| `LonghornVolumeRobustnessUnknown`  | Warning  | Volume     | 10 minutes                                                            |
| `LonghornVolumeFilesystemReadOnly` | Critical | Volume     | 5 minutes                                                             |
| `LonghornVolumeActualSpaceHigh`    | Warning  | Volume     | 15 minutes                                                            |
| `LonghornReplicaError`             | Critical | Replica    | 5 minutes                                                             |
| `LonghornReplicaUnknown`           | Warning  | Replica    | 10 minutes                                                            |
| `LonghornEngineError`              | Critical | Engine     | 5 minutes                                                             |
| `LonghornEngineUnknown`            | Warning  | Engine     | 10 minutes                                                            |
| `LonghornEngineReplicaModeError`   | Critical | Replica    | 5 minutes                                                             |
| `LonghornReplicaRebuildStalled`    | Warning  | Rebuild    | Approximately 60 minutes with the current expression and `for` period |
| `LonghornNodeNotReady`             | Critical | Node       | 5 minutes                                                             |
| `LonghornDiskNotReady`             | Warning  | Disk       | 10 minutes                                                            |
| `LonghornDiskSpaceLow`             | Warning  | Capacity   | 15 minutes                                                            |
| `LonghornDiskSpaceCritical`        | Critical | Capacity   | 5 minutes                                                             |
| `LonghornDiskUnhealthy`            | Critical | Disk       | 5 minutes                                                             |
| `LonghornManagerMetricsMissing`    | Critical | Monitoring | 10 minutes                                                            |

---

# Related Documentation

* [Metric Validation](metric-validation.md)
* [Troubleshooting Runbook](runbook.md)
* [Project README](../README.md)
