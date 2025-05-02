# Collection Details

## Overview
This document provides transparency about the output collected when running the logs collector script. The collection is designed to gather necessary troubleshooting information while respecting privacy and security concerns

Where possible output from the collection is sanitized, however we recommend you check a log collection and remove or edit any sensitive data

### Node-level collection

Output that is collected only from the node where the logs collector script is run

#### Operating System
- General OS configuration, for example: the hostname, resources, process list, service list, packages, limits and tunables
- Networking, iptables, netstat, interfaces, CNI configuration
- Journalctl output for related services if available, a list of services is listed in [the `JOURNALD_LOGS` variable](https://github.com/rancherlabs/support-tools/blob/master/collection/rancher/v2.x/logs-collector/rancher2_logs_collector.sh#L12) 
- OS logs from /var/logs, a list of log files is listed in [the `VAR_LOG_FILES` variable](https://github.com/rancherlabs/support-tools/blob/master/collection/rancher/v2.x/logs-collector/rancher2_logs_collector.sh#L15)

#### Kubernetes
- Distribution logs, for example rke2 and k3s agent/server journalctl logs
- Distribution configuration, rke2 and k3s configuration files, static pod manifests
- Container runtime logs and configuration, containerd or docker

### Cluster-level collection

Output that is collected from the cluster

Note, pod logs from other nodes and additional kubectl output can only be collected when running on a control plane/server node

#### Kubernetes
- Kubernetes control plane and worker component configuration and logs, for example: kubelet etcd, kube-apiserver
- Kubernetes pod logs from related namespaces, a list of namespaces is listed in [the `SYSTEM_NAMESPACE` variable](https://github.com/rancherlabs/support-tools/blob/master/collection/rancher/v2.x/logs-collector/rancher2_logs_collector.sh#L6) located in the script
- Directory listings, for example: rke2 manifests directory, SSL certificates, etcd snapshots

#### Kubectl output
- Kubectl list of nodes, pods, services, RBAC roles, persistent volumes, events, ingress and deployments
- Cluster provisioning CRD objects