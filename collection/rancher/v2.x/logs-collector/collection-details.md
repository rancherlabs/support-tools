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

### Logs Bundle Directory Structure
The following section provides a high-level overview of the directories and files created by the logs collector. It is intended to help support quickly locate commonly used troubleshooting data within a collected support bundle.

#### Top-level directories

| Directory | Contents |
|-----------|----------|
| `systeminfo/` | Host OS, CPU, memory, mounts, processes, sysctl, services, NetworkManager configs, iostat, pidstat, lsof, etc. |
| `networking/` | iptables/ip6tables, nftables, routes, interfaces, neighbors, ss/netstat, IPVS, CNI configs, ethtool output. |
| `systemlogs/` | `/var/log` files (syslog, messages, audit, cloud-init, dmesg, docker, etc.) and atop/sysstat data. |
| `journald/` | Journal output for RKE2, K3s, kubelet, containerd, Docker, rancher-system-agent, etc. |
| `docker/` | Docker information, images, daemon configuration (RKE only). |
| `rancher/` | Rancher container logs and inspect output (RKE). |
| `etcd/` | etcd health, alarms, metrics, snapshots, members, and database metadata. |
| `kubeadm/` | kubeadm resources, PKI, manifests, and pod logs. |
| `${DISTRO}/` | Primary cluster-specific collection (RKE2, K3s, or RKE). |

#### `${DISTRO}/`

This directory contains the majority of the Kubernetes and Rancher troubleshooting data.

##### `kubectl/`
Includes cluster resources (nodes, pods, services, endpoints, ConfigMaps, namespaces, Deployments, DaemonSets, StatefulSets, ReplicaSets, Jobs, CronJobs, Events, Ingresses, NetworkPolicies, PVs, PVCs, CRDs, ClusterRoles, ClusterRoleBindings, HelmCharts, Leases, HPAs, Roles, RoleBindings, and Rancher provisioning CRDs).

###### `kubectl/poddescribe/`
One `kubectl describe pod` output file for each system namespace.

##### `kubectl/rancher-prov/`
Rancher provisioning CRDs and infrastructure provider resources.

##### `podlogs/`
Pod logs for system namespaces. Helm Job logs are also collected here if the Job pod still exists.

##### `containerlogs/` *(RKE only)*
Static Kubernetes component logs (etcd, kube-apiserver, kube-controller-manager, kube-scheduler, kube-proxy, kubelet, nginx-proxy).

##### `containerinspect/`
Docker inspect output for system containers.

##### `podinspect/`
Docker inspect output for Kubernetes-managed containers.

##### `crictl/`
CRI runtime information (ps, pods, info, stats, images, versions, imagefsinfo).

##### `pod-manifests/`
Static pod manifests for control plane components.

##### `agent-logs/` / `server-logs/`
RKE2 agent and server logs within the requested date range.

##### `directories/`
Filesystem and certificate directory listings.

##### `certs/`
Decoded certificates.

#### Additional files

- `summary.txt`
- `versions`
- `collector-output.log`

  
