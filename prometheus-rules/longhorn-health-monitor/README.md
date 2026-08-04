# longhorn-health-monitor

## Overview

The Longhorn Health Monitor provides proactive alerting for Longhorn storage health using Prometheus and Rancher Monitoring.

The monitor focuses on:

- Volume Health
- Replica Health
- Engine Health
- Node Health
- Disk Health
- Capacity Monitoring
- Metrics Availability

This project intentionally does **not** monitor Longhorn backups.

For backup monitoring, see:

https://github.com/pitshou243/longhorn-backup-silent-failure-alerter

---
## Prerequisites

Before deploying the Longhorn Health Monitor, ensure that the following
components are available.

### Required Components

* A Kubernetes cluster with Longhorn or SUSE Storage installed.
* A running Prometheus instance.
* Prometheus Operator support for the `PrometheusRule` custom resource.
* Longhorn metrics available to Prometheus.
* Permission to create resources in the Prometheus monitoring namespace.
* `kubectl` access to the cluster.

For Rancher-managed clusters, the expected monitoring stack is typically
Rancher Monitoring.

### Longhorn Metrics

Prometheus must be able to scrape the Longhorn Manager metrics endpoint.

Verify that Longhorn metrics are available before installing the alert rules:

```promql
longhorn_volume_robustness
```

The query should return one or more Longhorn volumes.

You can also validate the Longhorn Manager metrics endpoint directly:

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
  grep '^longhorn_'
```

For additional validation steps, see
[Metric Validation](docs/metric-validation.md).

### PrometheusRule Support

Confirm that the `PrometheusRule` custom resource is installed:

```bash
kubectl get crd prometheusrules.monitoring.coreos.com
```

Expected result:

```text
prometheusrules.monitoring.coreos.com
```

Confirm that Prometheus is configured to select the namespace and labels used
by the Longhorn Health Monitor.

The default deployment manifest uses:

```yaml
metadata:
  namespace: cattle-monitoring-system
  labels:
    release: rancher-monitoring
```

These values are intended for Rancher Monitoring and may need to be changed
for other Prometheus deployments.

### Required Permissions

The user applying the rules must have permission to:

* Read Longhorn resources in `longhorn-system`.
* Read Kubernetes nodes, pods, events, PVs, and PVCs.
* Create, update, and delete `PrometheusRule` resources.
* Read Prometheus and Alertmanager status when troubleshooting.

### Optional Components

The following components are optional but recommended:

* Grafana for importing the provided dashboard.
* Alertmanager for routing and grouping alerts.
* A Longhorn backup target for volume recovery.
* Centralized log collection for Longhorn and node logs.

---

## Compatibility

Metric availability varies between Longhorn versions. Some alerts in this
project require metrics that may not exist in older releases.

Validate every required metric before deploying the rules in production.

### Compatibility Matrix

| Component           | Supported or expected configuration                                        |
| ------------------- | -------------------------------------------------------------------------- |
| Kubernetes          | A version supported by the installed Longhorn or SUSE Storage release      |
| Longhorn            | A release exposing all metrics used by the alert rules                     |
| SUSE Storage        | A supported release based on Longhorn                                      |
| Prometheus          | Prometheus managed directly or through Prometheus Operator                 |
| Prometheus Operator | Required for `PrometheusRule` resources                                    |
| Rancher Monitoring  | Supported when the rule namespace and release label match the installation |
| Grafana             | Required only when importing the provided dashboard                        |
| Alertmanager        | Required only for alert notification routing                               |

### Metrics Used by the Alert Rules

The alert rules currently depend on the following metrics:

```text
longhorn_volume_robustness
longhorn_volume_file_system_read_only
longhorn_volume_actual_size_bytes
longhorn_volume_capacity_bytes
longhorn_replica_state
longhorn_engine_state
longhorn_engine_replica_mode
longhorn_engine_rebuild_progress
longhorn_node_status
longhorn_disk_status
longhorn_disk_health
longhorn_disk_capacity_bytes
longhorn_disk_usage_bytes
longhorn_disk_reservation_bytes
longhorn_manager_cpu_usage_millicpu
```

Run the validation procedure in
[Metric Validation](docs/metric-validation.md) to confirm that these metrics
exist in the target environment.

### Version-Specific Metrics

Some metrics were introduced or changed in later Longhorn versions.

For example, the following alerts may remain inactive when their required
metrics are not exposed by the installed Longhorn release:

* `LonghornVolumeFilesystemReadOnly`
* `LonghornEngineReplicaModeError`
* `LonghornReplicaRebuildStalled`
* `LonghornDiskUnhealthy`
* `LonghornManagerMetricsMissing`

An inactive alert does not necessarily mean that the monitored condition is
healthy. It may mean that the required metric is unavailable.

### Rancher Monitoring

The default manifest assumes Rancher Monitoring uses:

```yaml
namespace: cattle-monitoring-system
```

and the following selector label:

```yaml
release: rancher-monitoring
```

Confirm the label used by the Prometheus instance:

```bash
kubectl -n cattle-monitoring-system get prometheus -o yaml
```

Review the `ruleSelector` and `ruleNamespaceSelector` fields.

If the monitoring installation uses a different release label, update the
`PrometheusRule` manifest before installation.

Example:

```yaml
metadata:
  namespace: <monitoring-namespace>
  labels:
    release: <prometheus-release-label>
```

### Non-Rancher Prometheus Deployments

For a standalone Prometheus Operator installation, update:

* The `PrometheusRule` namespace
* The release or selector labels
* Any cluster labels expected by the dashboard
* The Grafana datasource during dashboard import

Example:

```yaml
metadata:
  name: longhorn-health-monitor
  namespace: monitoring
  labels:
    prometheus: main
```

The exact labels must match the `ruleSelector` configured on the Prometheus
resource.

### Dashboard Compatibility

The dashboard requires a Prometheus datasource containing Longhorn metrics.

During import:

1. Select the Prometheus datasource used for Longhorn monitoring.
2. Confirm that dashboard variables return values.
3. Confirm that the cluster and namespace labels used by the dashboard exist.
4. Update dashboard queries when the environment uses different external
   labels.

### Validation Before Production

Before enabling notifications in production:

1. Confirm that every required metric returns data.
2. Confirm that the `PrometheusRule` is discovered by Prometheus.
3. Confirm that the rules appear in the Prometheus Rules page.
4. Confirm that dashboard panels display Longhorn data.
5. Review and adjust thresholds.
6. Test at least one alert in a non-production environment.
7. Confirm that Alertmanager routes the alert to the intended receiver.

### Tested Versions

Document versions that have been validated by the project maintainers.

Use the following table and update it as testing is completed:

| Component          | Tested version | Status             | Notes                              |
| ------------------ | -------------- | ------------------ | ---------------------------------- |
| Longhorn           | `1.11.2`    | Not yet documented | Validate all required metrics      |
| Rancher Monitoring | `<version>`    | Not yet documented | Validate rule selectors and labels |
| Kubernetes         | `<version>`    | Not yet documented | Must be supported by Longhorn      |
| Grafana            | `<version>`    | Not yet documented | Validate dashboard import          |
| Prometheus         | `<version>`    | Not yet documented | Validate rule evaluation           |

> [!NOTE]
> Do not list a version as tested unless the alert rules and dashboard were
> validated against that version.


---

## Features

- PrometheusRule alerts
- Rancher Monitoring compatible
- Grafana dashboard
- Runbook documentation
- Metric validation guide

---

## Installation

```bash
kubectl apply -f deploy/longhorn-health-rules.yaml
```

---

## Documentation

| Document | Description |
|----------|-------------|
| docs/metric-validation.md | Verify Longhorn metrics |
| docs/alert-reference.md | Complete alert descriptions |
| docs/runbook.md | Troubleshooting guide |

---

## Repository Layout

```text
deploy/
dashboards/
docs/
examples/
```

---

## License

Apache-2.0
