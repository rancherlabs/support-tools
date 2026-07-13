# etcd-monitor
Monitor RKE2 exposed etcd metrics to increase Cluster stability

etcd already exposes Prometheus metrics for member health, DB size, disk fsync latency, and leader changes. RKE2 also documents metrics support for cluster components, including etcd.   
The rules in this repo can be used to monitor etcd and alerts when treshold is reached.

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
Download the etcd-monitor.yaml and apply it to your cluster

kubectl apply -f etcd-monitor.yaml


