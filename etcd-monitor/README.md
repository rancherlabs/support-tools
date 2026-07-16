# etcd-monitor
Monitor RKE2 exposed etcd metrics to increase Cluster stability

etcd already exposes Prometheus metrics for member health, DB size, disk fsync latency, and leader changes. RKE2 also documents metrics support for cluster components, including etcd.   
The rules in this repo can be used to monitor etcd and alert when the threshold is reached. They are designed to integrate seamlessly with the rancher-monitoring stack.

## What it monitors

- etcd member availability
- etcd leader presence
- leader election frequency
- database size and growth rate
- WAL fsync latency
- backend commit latency
- apply/request latency
- etcd quota usage
- member count and quorum risk

## How to use it
Download the either the `etcd-monitor.yaml` or `etcd-monitor-extended.yaml` and apply it to the cluster

**Option 1: Standard Monitoring (Recommended)**
Provides essential coverage for quorum loss, leader elections, high disk latency, and quota exhaustion.
- `kubectl apply -f etcd-monitor.yaml`
**Option 2: Extended Monitoring**
Includes the standard alerts plus deeper insights into apply latencies, read index slowness, and proposal backlogs (useful for high-load clusters).
- `kubectl apply -f etcd-monitor-extended.yaml`



