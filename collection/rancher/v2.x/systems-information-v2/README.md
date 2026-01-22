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
Run on Mon Jan 19 03:03:10 UTC 2026

NAME                       READY   STATUS    RESTARTS      AGE
rancher-6954467f5f-nfz99   1/1     Running   3 (21d ago)   46d
Rancher version: v2.12.4
Rancher id: c08f2685-9267-4048-8eed-03a97dd04c26

Cluster Id     Name          K8s Version       Provider   Created                Nodes
c-m-5nngjk9q   test          v1.30.11+rke2r1   rke2       2024-01-24T05:19:10Z   <none>
c-m-c8jjqv28   elemental-1   v1.32.3+rke2r1    rke2       2025-04-30T03:38:05Z   <none>
local          local         v1.32.3+rke2r1    rke2       2023-03-29T22:02:04Z   <none>

--------------------------------------------------------------------------------
Cluster: test (c-m-5nngjk9q)
Node Id         Address                      etcd   CP     W      CPU   RAM         OS                   Created
machine-ndlwc   10.99.12.83,ip-10-99-12-83   true   true   true   2     3941260Ki   Ubuntu 24.04.2 LTS   2025-05-12T04:26:22Z

Node count:         1
Control Plane CPUs: 2
Worker Node CPUs:   2
Cluster Total CPUs: 2

--------------------------------------------------------------------------------
Cluster: elemental-1 (c-m-c8jjqv28)
Node Id         Address                                                etcd   CP     W      CPU   RAM         OS                     Created
machine-jchnz   192.168.205.2,m-357797b0-76e6-44c1-9fb5-7402e448b1ab   true   true   true   4     4010116Ki   SUSE Linux Micro 6.0   2025-04-30T04:29:03Z

Node count:         1
Control Plane CPUs: 4
Worker Node CPUs:   4
Cluster Total CPUs: 4

--------------------------------------------------------------------------------
Cluster: local (local)
Node Id         Address                        etcd   CP     W       CPU   RAM         OS                   Created
machine-g7gcj   10.99.12.180,ip-10-99-12-180   true   true   false   2     8071616Ki   Ubuntu 24.04.2 LTS   2023-03-29T22:02:38Z

Node count:         1
Control Plane CPUs: 2
Worker Node CPUs:   0
Cluster Total CPUs: 2
--------------------------------------------------------------------------------
GLOBAL SUMMARY
Total Nodes:              3
Total Control Plane CPUs: 8
Total Worker CPUs:        6
Total Aggregate CPUs:     8
```