# RKE2 Monitor

## Overview

RKE2 Monitor is a collection of Prometheus alerting rules that helps identify common RKE2 cluster issues before they become service-impacting incidents.

The alerts are designed to provide early visibility into the health of the Kubernetes control plane, worker nodes, networking components, system workloads, and certificates, allowing administrators to detect and investigate problems before they escalate into outages.

The project currently provides:

- PrometheusRule resources for Prometheus Operator and Rancher Monitoring

## Disclaimer

This project provides example Prometheus alerting rules intended to assist with monitoring and troubleshooting RKE2 clusters.

These rules should be reviewed and adjusted to meet the operational requirements of your environment. Alert thresholds, durations, and expressions may require tuning depending on cluster size, workload characteristics, Kubernetes version, and monitoring configuration.

Some alerts depend on metrics that may not be available in every deployment. Always validate the rules in a non-production environment before deploying them to production clusters.

---

## Purpose

Many RKE2 incidents exhibit warning signs before users experience an outage. These alert rules are intended to identify those warning signs early and provide actionable information for troubleshooting.

| Failure Pattern | Typical Symptoms |
|----------------|------------------|
| API server degradation | Slow API responses, 5xx errors, failing health probes |
| Kubelet instability | Pods stuck in Pending or ContainerCreating |
| Node resource pressure | MemoryPressure, DiskPressure, high I/O wait |
| Container runtime degradation | Container startup failures, runtime errors |
| DNS failures | CoreDNS failures, increased SERVFAIL responses |
| CNI instability | Unhealthy Canal, Calico, Cilium, or Flannel components |
| Certificate expiration | Authentication failures due to expiring kubelet certificates |
| Disk exhaustion | Image pull failures, etcd instability |
| Control plane component failures | Scheduler or controller-manager unavailable |

---

## Metrics Used

The alert rules evaluate metrics provided by existing monitoring components.

| Component | Metrics Source |
|----------|----------------|
| kube-apiserver | Kubernetes control plane metrics |
| kube-scheduler | Kubernetes control plane metrics |
| kube-controller-manager | Kubernetes control plane metrics |
| kubelet | kubelet metrics |
| Container runtime | kubelet runtime metrics |
| Node health | node-exporter |
| Kubernetes resources | kube-state-metrics |
| DNS | CoreDNS metrics |
| CNI components | kube-state-metrics |
| Kubelet certificates | kubelet certificate metrics |

No additional exporters are installed by this project.

---

## Included Alerts

### Control Plane Health

| Alert | Description |
|------|-------------|
| `RKE2KubeAPIServerDown` | Detects unavailable API servers |
| `RKE2KubeAPIServerHighErrorRate` | Detects elevated API server error rates |
| `RKE2KubeAPIServerHighLatency` | Detects slow API server responses |
| `RKE2KubeControllerManagerDown` | Detects unavailable controller-manager instances |
| `RKE2KubeSchedulerDown` | Detects unavailable scheduler instances |

### Node Health

| Alert | Description |
|------|-------------|
| `RKE2NodeNotReady` | Detects nodes reporting NotReady |
| `RKE2NodeMemoryPressure` | Detects memory pressure conditions |
| `RKE2NodeDiskPressure` | Detects disk pressure conditions |
| `RKE2NodeFilesystemAlmostFull` | Detects low filesystem capacity |
| `RKE2NodeHighIOWait` | Detects excessive storage I/O wait |

### Kubelet and Runtime Health

| Alert | Description |
|------|-------------|
| `RKE2KubeletDown` | Detects unavailable kubelets |
| `RKE2ContainerRuntimeErrors` | Detects container runtime errors |
| `RKE2PodStartupLatencyHigh` | Detects increased pod startup latency |

### Networking and DNS

| Alert | Description |
|------|-------------|
| `RKE2CNIPluginPodsNotReady` | Detects unhealthy CNI components |
| `RKE2CoreDNSNotReady` | Detects unavailable CoreDNS pods |
| `RKE2CoreDNSHighErrorRate` | Detects elevated CoreDNS error responses |

### Workload Stability

| Alert | Description |
|------|-------------|
| `RKE2SystemPodsCrashLooping` | Detects frequent restarts of critical system pods |
| `RKE2SystemPodPending` | Detects critical system pods remaining Pending |
| `RKE2SystemPodFailed` | Detects failed system pods |

### Certificate Health

| Alert | Description |
|------|-------------|
| `RKE2KubeletClientCertificateExpiringSoon` | Detects kubelet client certificates approaching expiration |
| `RKE2KubeletServerCertificateExpiringSoon` | Detects kubelet server certificates approaching expiration |

---

## Requirements

The following monitoring components must already be deployed:

| Component | Purpose |
|----------|---------|
| Prometheus | Evaluates alert rules |
| Prometheus Operator or Rancher Monitoring | Manages PrometheusRule resources |
| kube-state-metrics | Provides Kubernetes object metrics |
| node-exporter | Provides host-level metrics |
| CoreDNS metrics | Enables DNS-related alerts |
| kubelet metrics | Enables kubelet and runtime alerts |

These components are typically available when using Rancher Monitoring or another Prometheus Operator-based monitoring stack.

---

## Installation

Apply the alert rules:

```bash
kubectl apply -f rke2-monitor.yaml
```

Verify that the PrometheusRule resource was created:

```bash
kubectl get prometheusrule
```

Describe the resource to ensure Prometheus accepted the rules:

```bash
kubectl describe prometheusrule rke2-monitor
```

---

## Verification

Confirm that Prometheus has loaded the alert rules.

```promql
ALERTS{alertname=~"RKE2.*"}
```

You can also verify that the required metrics exist before enabling alerts.

Example:

```promql
up{job=~".*kube-apiserver.*"}
```

```promql
kube_node_status_condition
```

```promql
node_filesystem_avail_bytes
```

---

## Customization

Every environment is different. You may wish to customize:

- Alert thresholds
- Alert durations (`for`)
- Namespace filters
- Job name selectors
- CNI pod selectors
- Alert labels and severity levels

Adjust the rules to align with your operational requirements before deploying them to production.

---

## Compatibility

RKE2 Monitor has been designed for environments using:

- RKE2
- Rancher Monitoring
- Prometheus Operator
- kube-state-metrics
- node-exporter

Some alerts require optional metrics or collectors to be enabled. If the required metrics are unavailable, the corresponding alerts will remain inactive.
