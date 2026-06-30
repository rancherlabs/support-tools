# Rancher Logs Collector Output Structure

This document summarizes the directories and files created by the
Rancher Logs Collector under `${TMPDIR}`.

## Top-level directories

  -----------------------------------------------------------------------
  Directory                             Contents
  ------------------------------------- ---------------------------------
  `systeminfo/`                         Host OS, CPU, memory, mounts,
                                        processes, sysctl, services,
                                        NetworkManager configs, iostat,
                                        pidstat, lsof, etc.

  `networking/`                         iptables/ip6tables, nftables,
                                        routes, interfaces, neighbors,
                                        ss/netstat, IPVS, CNI configs,
                                        ethtool output.

  `systemlogs/`                         `/var/log` files (syslog,
                                        messages, audit, cloud-init,
                                        dmesg, docker, etc.) and
                                        atop/sysstat data.

  `journald/`                           `journalctl` output for rke2,
                                        k3s, kubelet, containerd, docker,
                                        rancher-system-agent, etc.

  `docker/`                             Docker info, ps, stats, images,
                                        daemon.json (RKE only).

  `rancher/`                            Rancher container logs and
                                        container inspect output (RKE).

  `etcd/`                               etcd endpoint health, alarms,
                                        metrics, snapshots, member list,
                                        DB metadata.

  `kubeadm/`                            kubeadm-specific kubectl output,
                                        pod logs, PKI, static pod
                                        manifests.

  `${DISTRO}/`                          Main cluster-specific collection
                                        (rke2, k3s, rke, pod).
  -----------------------------------------------------------------------

# `${DISTRO}/` Structure

This is where most of the Rancher-specific data is collected.

## `${DISTRO}/kubectl/`

Contains:

-   nodes
-   nodesdescribe
-   nodes.json
-   pods
-   services
-   endpoints
-   configmaps
-   namespaces
-   version
-   api-resources
-   apps

### Cluster-scoped resources

-   clusterroles
-   clusterrolebindings
-   crds
-   mutatingwebhookconfigurations
-   validatingwebhookconfigurations
-   pv
-   volumeattachments
-   globalnetworkpolicies.projectcalico.org

### Namespaced resources

-   deployments
-   daemonsets
-   statefulsets
-   replicasets
-   pods
-   jobs
-   cronjobs
-   events
-   ingress
-   networkpolicies
-   helmcharts
-   leases
-   hpa
-   roles
-   rolebindings
-   configmaps
-   endpoints
-   pvc

## `${DISTRO}/kubectl/poddescribe/`

Contains one file per system namespace, including:

-   kube-system
-   cattle-system
-   cattle-fleet-system
-   cattle-monitoring-system
-   longhorn-system
-   ...

Each file contains:

``` text
kubectl describe pod -n <namespace>
```

output.

## `${DISTRO}/kubectl/rancher-prov/`

Provisioning CRDs collected include:

-   clusters.management.cattle.io
-   clusters.fleet.cattle.io
-   nodes.management.cattle.io
-   rkeclusters.rke.cattle.io
-   rkecontrolplanes.rke.cattle.io
-   clusters.provisioning.cattle.io
-   amazonec2machines.\*
-   azuremachines.\*
-   harvestermachines.\*
-   linodemachines.\*
-   vmwarevspheremachines.\*

Additionally:

-   cattle-controller-cfgmap

## `${DISTRO}/podlogs/`

Contains logs for every pod in namespaces such as:

-   kube-system
-   cattle-system
-   cattle-fleet-system
-   cattle-monitoring-system
-   longhorn-system
-   ...

Each pod typically produces:

-   namespace-podname
-   namespace-podname-previous

This is also where Helm Job logs are collected if the Job pod still
exists.

## `${DISTRO}/containerlogs/`

RKE-only container logs:

-   etcd
-   kube-apiserver
-   kube-controller-manager
-   kube-scheduler
-   kube-proxy
-   kubelet
-   nginx-proxy

## `${DISTRO}/containerinspect/`

Docker inspect output for the above containers.

## `${DISTRO}/podinspect/`

Docker inspect output for Kubernetes system containers.

## `${DISTRO}/crictl/`

Contains:

-   psa
-   pods
-   info
-   statsa
-   version
-   images
-   imagefsinfo
-   crictl-version
-   containerd-version
-   runc-version

## `${DISTRO}/pod-manifests/`

RKE2 static pod manifests, including:

-   kube-apiserver.yaml
-   kube-controller-manager.yaml
-   kube-scheduler.yaml
-   etcd.yaml
-   ...

## `${DISTRO}/agent-logs/`

Copies of:

-   `/var/lib/rancher/rke2/agent/logs`

within the requested date window.

## `${DISTRO}/server-logs/`

Copies of:

-   `/var/lib/rancher/rke2/server/logs`

within the requested date window.

## `${DISTRO}/directories/`

Directory listings such as:

-   k3sagent
-   k3sservermanifests
-   k3sservertls
-   findetckubernetesssl
-   findoptrkeetckubernetesssl

Useful for certificate and directory layout troubleshooting.

## `${DISTRO}/certs/`

Decoded certificates stored under:

-   agent/
-   server/

or

-   certs/\*.pem
-   tmpcerts/\*.pem

depending on the distribution.

# Additional files at the collection root

Besides directories, the collector also generates:

-   summary.txt
-   versions
-   collector-output.log
