# Kubernetes Client Throttling Monitor

A lightweight bash utility to detect client-side API throttling (`rest_client_rate_limiter_duration_seconds`) across core Kubernetes components. 

When deploying clusters without a centralised monitoring stack (like Prometheus) installed, diagnosing control plane bottlenecks can be difficult. This tool acts as a drop-in alternative to PromQL queries by scraping the `/metrics` endpoints directly using the local cluster certificates.

Currently supports:
- **RKE2**
- **K3s**

## How it works

Kubernetes components use client-go to communicate with the `kube-apiserver`. To protect the API server, client-go implements client-side rate limiting (QPS and Burst limits). When a component hits this limit, it artificially pauses its own requests, leading to slow reconciliation loops, degraded cluster performance, and delayed scaling.

This script takes a baseline snapshot of the metrics, loops continuously every 10 seconds, and calculates two values:
1. **Intensity (s/s):** The total seconds the component spent paused, divided by the wall-clock interval. 
2. **Penalty (s/req):** The average delay added to a single API request due to throttling.

## Usage

Run the script as `root` (or with `sudo`) directly on any server or agent (worker) node:

```bash
sudo bash ./k8s-throttle-monitor.sh
```

### Interpreting the Output

```text
Detected Distribution: rke2 (server)
Capturing initial baseline...
Starting continuous monitoring (Press Ctrl+C to stop)...
------------------------------------------------------------
COMPONENT                 INTENSITY (s/s) PENALTY (s/req)
------------------------------------------------------------

--- Snapshot taken at 15:33:04 (Interval: 10s) ---
kube-apiserver            0.0000          0.0000         
kube-proxy                0.0000          0.0000         
kube-controller-manager   0.4500          0.0012         
kube-scheduler            0.0000          0.0000         
kubelet                   0.0000          0.0000         
```

* **Any value > 0** indicates that the component is actively hitting its client-side rate limit.
* In the example above, the `kube-controller-manager` is being throttled, spending 0.45 seconds out of every 10 seconds artificially paused. 

## Resolution

If a component is actively throttling, you can increase its limits by passing additional arguments to the respective component's configuration.

### Standalone clusters

For example, to adjust the `kube-api-qps` and `kube-api-burst` limits for [kube-controller-manager](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/) on an **RKE2** cluster, you would add the following to `/etc/rancher/rke2/config.yaml`:

```yaml
kube-controller-manager-arg:
  - "kube-api-qps=100"
  - "kube-api-burst=200"
```

Another example, to adjust the [kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/):
```yaml
kubelet-arg:
  - "kube-api-qps=100"
  - "kube-api-burst=200"
```

For **K3s**, the equivalent configuration would be added to `/etc/rancher/k3s/config.yaml` 

Restart the respective service (`systemctl restart rke2-server`, `systemctl restart rke2-agent`, or `systemctl restart k3s`) for the changes to take effect.

### Clusters provisioned by Rancher

For clusters provisioned and managed by **Rancher**, these arguments should be added to the Cluster Configuration via the Rancher dashboard or Terraform. 

For more details on modifying cluster arguments, see the official SUSE knowledge base article:
[How to Update or Add Arguments to the kube-apiserver in RKE2 and K3s Clusters](https://support.scc.suse.com/s/kb/How-to-Update-or-Add-Arguments-to-the-kube-apiserver-in-RKE2-and-K3s-Clusters)