# Longhorn Support Bundle Script

## Notes

This script is intended to collect diagnostic information from Kubernetes clusters running Longhorn, including:
- Logs from all containers in the `longhorn-system` namespace
- YAML definitions of Kubernetes resources in the `longhorn-system` namespace
- Longhorn Custom Resource Definitions and their instances
- Kubernetes cluster information and node details
- Events and metrics related to the cluster and Longhorn operations

This script helps gather comprehensive information needed for troubleshooting Longhorn-related issues, while ensuring no sensitive information like Kubernetes Secrets is collected.

Output will be written to the current directory as a tar.gz archive named `longhorn-support-bundle-YYYY-MM-DD-HH-MM-SS.tar.gz`.

## Usage

The script needs to be downloaded and run by a user with sufficient permissions to access the Kubernetes cluster via `kubectl`.

### Download and run the script
* Save the script as: `longhorn-support-bundle.sh`

  Using `wget`:
    ```bash
    wget https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/longhorn/run.sh
    ```
  Using `curl`:
    ```bash
    curl -OLs https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/longhorn/run.sh
    ```
 
* Make the script executable:
    ```bash
    chmod +x longhorn-support-bundle.sh
    ```

* Run the script:
  ```bash
  bash ./longhorn-support-bundle.sh
  ```

## Bundle Contents

The script creates a support bundle with the following structure:

```
longhorn-support-bundle-YYYY-MM-DD-HH-MM-SS/
├── logs/                          # Pod logs from longhorn-system
│   └── longhorn-system/
│       └── [pod-name]/
│           ├── [container-name].log
│           └── [container-name]-previous.log
│
├── yamls/                         # YAML definitions of various resources
│   ├── cluster/                   # Cluster-scoped resources
│   │   └── kubernetes/
│   │       ├── nodes.yaml         # All nodes in the cluster
│   │       ├── events.yaml        # Cluster-wide events
│   │       └── version.yaml       # Kubernetes version information
│   │
│   └── namespaced/                # Namespace-scoped resources
│       └── longhorn-system/
│           ├── kubernetes/        # Standard Kubernetes resources
│           │   ├── pods.yaml
│           │   ├── services.yaml
│           │   ├── deployments.yaml
│           │   ├── daemonsets.yaml
│           │   ├── statefulsets.yaml
│           │   ├── configmaps.yaml
│           │   ├── persistentvolumeclaims.yaml
│           │   ├── replicasets.yaml
│           │   └── events.yaml    # Namespace-specific events
│           │
│           └── longhorn/          # Longhorn CRDs
│               ├── engines.yaml
│               ├── volumes.yaml
│               ├── nodes.yaml
│               └── ...
│
├── nodes/                         # Per-node information
│   └── [node-name]/
│       ├── node.yaml              # Complete node YAML definition
│       ├── description.txt        # Output of kubectl describe node
│       ├── metrics.txt            # Resource usage metrics
│       ├── capacity.json          # Node capacity information
│       └── allocatable.json       # Node allocatable resources
│
└── external/                      # For additional external resources
```

## Information Collected

The script collects the following information:

1. **Kubernetes Resources in the `longhorn-system` namespace:**
   - Pods, Services, Deployments, DaemonSets, StatefulSets
   - ConfigMaps, PersistentVolumeClaims, ReplicaSets
   - Does NOT include Secrets

2. **Longhorn Custom Resources:**
   - All Custom Resource Definitions with the API group `longhorn.io`
   - Instances of these CRDs in the `longhorn-system` namespace

3. **Pod Logs:**
   - Current and previous (if available) logs for all containers in all pods in the `longhorn-system` namespace

4. **Cluster Information:**
   - Kubernetes version
   - Cluster-wide events
   - Node information

5. **Per-Node Details:**
   - Complete YAML definition
   - Detailed node description
   - Resource capacity and allocation
   - Current metrics (if available)

## Requirements

- A Kubernetes cluster with Longhorn installed
- `kubectl` installed and configured to access your cluster
- Sufficient permissions to read resources in the `longhorn-system` namespace and cluster-level resources

## Privacy and Security

This script does not collect Kubernetes Secrets or sensitive credentials. However, be aware that logs and configuration data may contain sensitive information. Review the bundle before sharing it externally.