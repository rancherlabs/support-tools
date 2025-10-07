# Rancher 2.x Systems Summary v2

The script runs as a pod in the Rancher Management (local) cluster and collects information about the clusters managed by Rancher. The script collects the following information:

- Rancher server version and installation UUID
- Details of all clusters managed by Rancher, including:
  - Cluster ID and name
  - Kubernetes version
  - Provider type
  - Creation timestamp
  - Nodes associated with each cluster
- For each cluster, detailed information about each node, including:
  - Node ID and address
  - Role within the cluster
  - CPU and RAM capacity
  - Operating system and Docker version
  - Creation timestamp
- Total count of nodes across all clusters

## How to use

Run the following command to deploy the script as a pod in the Rancher Management (local) cluster:

```bash
# Deploy the pod in the cluster
kubectl apply -f https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/systems-information-v2/deploy.yaml

# Wait for the pod to reach Succeeded status
while [[ $(kubectl get pod rancher-systems-summary-pod -n cattle-system -o 'jsonpath={..status.phase}') != "Succeeded" ]]; do
  echo "Waiting for rancher-systems-summary-pod to complete..."
  sleep 5
done

# Follow the logs from the pod
kubectl logs -f pod/rancher-systems-summary-pod -n cattle-system

# Clean up the pod
kubectl delete pod/rancher-systems-summary-pod -n cattle-system
```

> Note: It might take a few minutes for the pod to collect the information and display it in the logs. The script will exit after displaying the information, you should see `Total node count` at the end of the log output

Example output:

```bash
Rancher Systems Summary Report
==============================
Run on Tue Oct  7 14:44:27 UTC 2025

NAME                      READY   STATUS    RESTARTS        AGE
rancher-5d5896844-bkmlj   1/1     Running   2 (27d ago)     27d
rancher-5d5896844-t8hvc   1/1     Running   6 (6d14h ago)   27d
rancher-5d5896844-wcf7q   1/1     Running   1 (6d8h ago)    27d
Rancher version: v2.12.1
Rancher id: 57299729-c16b-4857-8a48-3a45f36b2b94

Cluster Id     Name             K8s Version      Provider    Created                Nodes
c-4kt65        3nuc-harvester   v1.32.4+rke2r1   harvester   2025-07-26T21:28:19Z   <none>
c-hcrk7        observability    v1.32.7+k3s1     k3s         2025-08-20T20:16:37Z   <none>
c-m-sh4jmcxr   rke2-harv        v1.32.6+rke2r1   rke2        2025-08-05T20:04:21Z   <none>
local          local            v1.32.6+k3s1     k3s         2025-07-26T21:23:04Z   <none>

--------------------------------------------------------------------------------
Cluster: 3nuc-harvester (c-4kt65)
Node Id         Address               etcd   Control Plane   Worker   CPU   RAM          OS                     Container Runtime Version   Created
machine-br42p   10.10.12.103,nuc-03   true   true            false    12    65544020Ki   Harvester v1.5.1-rc2   containerd://2.0.4-k3s2     2025-07-26T21:30:26Z
machine-f4zxg   10.10.12.101,nuc-01   true   true            false    12    65560396Ki   Harvester v1.5.1-rc2   containerd://2.0.4-k3s2     2025-07-26T21:30:26Z
machine-hqtmv   10.10.12.102,nuc-02   true   true            false    12    65544008Ki   Harvester v1.5.1-rc2   containerd://2.0.4-k3s2     2025-07-26T21:30:26Z
Node count: 3

--------------------------------------------------------------------------------
Cluster: observability (c-hcrk7)
Node Id         Address                         etcd   Control Plane   Worker   CPU   RAM          OS                     Container Runtime Version    Created
machine-4j4rp   10.10.12.182,observability-02   true   true            false    4     16381888Ki   SUSE Linux Micro 6.1   containerd://2.0.5-k3s2.32   2025-08-20T20:17:40Z
machine-8bs8x   10.10.12.181,observability-01   true   true            false    4     16381892Ki   SUSE Linux Micro 6.1   containerd://2.0.5-k3s2.32   2025-08-20T20:17:40Z
machine-z5khp   10.10.12.183,observability-03   true   true            false    4     16381892Ki   SUSE Linux Micro 6.1   containerd://2.0.5-k3s2.32   2025-08-20T20:17:40Z
Node count: 3

--------------------------------------------------------------------------------
Cluster: rke2-harv (c-m-sh4jmcxr)
Node Id         Address                                           etcd    Control Plane   Worker   CPU   RAM         OS                     Container Runtime Version   Created
machine-29qwr   10.10.15.94,rke2-harv-workers-sm-xv9q4-k9lnh      false   false           true     4     8137228Ki   SUSE Linux Micro 6.1   containerd://2.0.5-k3s1     2025-08-25T15:38:35Z
machine-f4hwq   10.10.15.80,rke2-harv-control-plane-92bsj-pf5tn   true    true            false    2     4015184Ki   SUSE Linux Micro 6.1   containerd://2.0.5-k3s1     2025-08-05T20:13:11Z
machine-fjftz   10.10.15.93,rke2-harv-workers-sm-xv9q4-s688w      false   false           true     4     8137228Ki   SUSE Linux Micro 6.1   containerd://2.0.5-k3s1     2025-08-25T15:29:59Z
machine-g6z62   10.10.15.77,rke2-harv-control-plane-92bsj-z6qcp   true    true            false    2     4015184Ki   SUSE Linux Micro 6.1   containerd://2.0.5-k3s1     2025-08-05T20:12:37Z
machine-gpbxx   10.10.15.92,rke2-harv-workers-sm-xv9q4-d5h8t      false   false           true     4     8137228Ki   SUSE Linux Micro 6.1   containerd://2.0.5-k3s1     2025-08-25T15:29:37Z
machine-l9sl6   10.10.15.76,rke2-harv-control-plane-92bsj-kdm4h   true    true            false    2     4015184Ki   SUSE Linux Micro 6.1   containerd://2.0.5-k3s1     2025-08-05T20:10:11Z
Node count: 6

--------------------------------------------------------------------------------
Cluster: local (local)
Node Id         Address                   etcd   Control Plane   Worker   CPU   RAM         OS                                    Container Runtime Version    Created
machine-bhffb   10.10.12.123,rancher-03   true   true            false    2     7730528Ki   SUSE Linux Enterprise Server 15 SP6   containerd://2.0.5-k3s2.32   2025-07-31T13:32:48Z
machine-mwx5g   10.10.12.122,rancher-02   true   true            false    2     7730536Ki   SUSE Linux Enterprise Server 15 SP6   containerd://2.0.5-k3s1.32   2025-07-26T21:23:21Z
machine-rnwmp   10.10.12.121,rancher-01   true   true            false    2     7730536Ki   SUSE Linux Enterprise Server 15 SP6   containerd://2.0.5-k3s1.32   2025-07-26T21:23:21Z
Node count: 3
--------------------------------------------------------------------------------
Total node count: 15
```
