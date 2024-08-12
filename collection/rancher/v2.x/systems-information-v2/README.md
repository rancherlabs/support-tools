# Rancher 2.x Systems Summary v2

The script runs as a pod in the Rancher 2.x cluster and collects information about the systems in the cluster. The script collects the following information:

- Rancher server version and installation UUID.
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
- Total count of nodes across all clusters.

## How to use

Run the following command to deploy the script as a pod in the Rancher local cluster:

```bash
# Deploy the pod in the cluster
kubectl apply -f https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/systems-information-v2/deploy.yaml

# Wait for the pod to reach Succeeded status
while [[ $(kubectl get pod rancher-systems-summary-pod -n cattle-system -o 'jsonpath={..status.phase}') != "Succeeded" ]]; do
  echo "Waiting for rancher-systems-summary-pod to complete..."
  sleep 5
done

# Grab the logs from the pod
kubectl logs pod/rancher-systems-summary-pod -n cattle-system

# Clean up the pod
kubectl delete pod/rancher-systems-summary-pod -n cattle-system
```

NOTE: It might take a few minutes for the pod to collect the information and display it in the logs. The script will delete the pod after displaying the information.

Example output:

```bash
Rancher Systems Summary Report
==============================
Run on Mon Aug 12 16:46:44 UTC 2024

NAME                       READY   STATUS    RESTARTS      AGE
rancher-747c5647d7-5fmh7   2/2     Running   3 (63m ago)   94m
rancher-747c5647d7-76hjr   2/2     Running   5 (61m ago)   101m
rancher-747c5647d7-sfmlc   2/2     Running   2 (35m ago)   92m
Rancher version: v2.9.0
Rancher id: b82b0b06-6f0b-4052-9f17-3602499f07dc

Cluster Id     Name             K8s Version           Provider   Created                Nodes
c-m-mfc8m8z5   a1-ops-prd       v1.30.2+rke2r1        imported   2024-01-27T20:16:15Z   <none>
c-m-tncnvhrs   a1-dell-r720     v1.27.13+rke2r1       rke2       2023-12-11T00:52:36Z   <none>
local          a1-rancher-prd   v1.30.2+rke2r1        rke2       2023-08-13T08:46:40Z   <none>

--------------------------------------------------------------------------------
Cluster: a1-ops-prd (c-m-mfc8m8z5)
Node Id         Address                                         Role     CPU   RAM           OS       Docker Version   Created
machine-4m5rd   172.28.2.217,a1-ops-prd-medium-7962bbf5-wrc2t   <none>   8     16273392Ki    <none>   <none>           2024-07-10T18:28:25Z
machine-4tvh7   172.28.2.142,a1-ops-prd-mgmt-105e966c-xvlg7     <none>   8     16273396Ki    <none>   <none>           2024-07-09T13:19:54Z
machine-5dnpc   172.28.2.234,a1-ops-prd-large-ba0dc7eb-tpmh8    <none>   12    49228384Ki    <none>   <none>           2024-07-12T06:33:51Z
machine-bpmld   172.28.2.235,a1-ops-prd-large-ba0dc7eb-2xzfv    <none>   12    49228376Ki    <none>   <none>           2024-07-12T06:39:50Z
machine-hnhqb   172.28.2.185,a1-ops-prd-mgmt-105e966c-b68bx     <none>   8     16273400Ki    <none>   <none>           2024-07-08T05:36:20Z
machine-j7ckv   172.28.2.220,a1-ops-prd-medium-7962bbf5-sptzb   <none>   8     16273412Ki    <none>   <none>           2024-07-10T18:34:02Z
machine-lvljm   172.28.2.218,a1-ops-prd-small-8918c748-9hjl7    <none>   4     8029568Ki     <none>   <none>           2024-07-10T18:32:48Z
machine-q8blw   172.28.2.205,a1-ops-prd-small-8918c748-5wz8n    <none>   4     8029568Ki     <none>   <none>           2024-07-10T17:58:51Z
machine-rslml   172.28.2.222,a1-ops-prd-small-8918c748-rs7tf    <none>   4     8029564Ki     <none>   <none>           2024-07-10T21:55:58Z
machine-sv2n2   172.28.2.167,a1-ops-prd-mgmt-105e966c-fbtdz     <none>   8     16273400Ki    <none>   <none>           2024-07-08T13:29:51Z
machine-v5mxt   172.28.2.219,a1-ops-prd-small-8918c748-r9knc    <none>   4     8029556Ki     <none>   <none>           2024-07-10T18:33:35Z
machine-vs9tn   172.28.2.223,a1-ops-prd-medium-7962bbf5-lqfwj   <none>   8     16273400Ki    <none>   <none>           2024-07-10T21:54:43Z
machine-xjwjv   172.28.2.236,a1-ops-prd-large-ba0dc7eb-sbrfm    <none>   12    49228388Ki    <none>   <none>           2024-07-12T06:47:55Z
machine-z674w   172.28.2.221,a1-ops-prd-small-8918c748-tlzvx    <none>   4     8029560Ki     <none>   <none>           2024-07-10T21:06:23Z
Node count: 14

--------------------------------------------------------------------------------
Cluster: a1-dell-r720 (c-m-tncnvhrs)
Node Id         Address                   Role     CPU   RAM           OS       Docker Version   Created
machine-4rbqg   172.28.2.22,a1hrr720p02   <none>   24    396150564Ki   <none>   <none>           2023-12-11T01:32:03Z
machine-f864m   172.28.2.24,a1hrr720p04   <none>   24    264029632Ki   <none>   <none>           2024-02-10T00:54:14Z
machine-p5lqp   172.28.2.21,a1hrr720p01   <none>   24    264030104Ki   <none>   <none>           2023-12-11T00:54:08Z
machine-srwm6   172.28.2.23,a1hrr720p03   <none>   24    396150588Ki   <none>   <none>           2023-12-11T03:12:46Z
machine-wfv9d   172.28.2.25,a1hrr720p05   <none>   24    264049860Ki   <none>   <none>           2024-02-10T01:01:46Z
Node count: 5

--------------------------------------------------------------------------------
Cluster: a1-rancher-prd (local)
Node Id         Address                     Role     CPU   RAM          OS       Docker Version   Created
machine-5xwg6   172.28.4.191,a1ubranvp-02   <none>   16    32761048Ki   <none>   <none>           2024-07-07T09:03:53Z
machine-kplk9   172.28.4.116,a1ubranvp-03   <none>   16    32761056Ki   <none>   <none>           2024-07-07T08:55:21Z
machine-tgqhj   172.28.4.160,a1ubranvp-01   <none>   16    32761060Ki   <none>   <none>           2024-07-07T09:03:53Z
Node count: 3
--------------------------------------------------------------------------------
Total node count: 22
```
