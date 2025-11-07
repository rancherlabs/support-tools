# SCC Operator Collector - Collection Details

This document outlines the specific information gathered by the `scc-operator-collector.sh` script. The collected data is organized into a directory structure within the support bundle.

## Bundle Structure

The support bundle has the following structure:

```
<bundle-name>/
├── cluster-info/
├── configmaps/
├── crds/
├── events/
├── leases/
├── operator-pods/
├── registrations/
├── secrets/
├── metadata.txt
```

---

## Collected Information

### 1. Cluster Information (`cluster-info/`)

General information about the Rancher `local` Kubernetes cluster.

- **`cluster-info.txt`**: Output of `kubectl cluster-info`.
- **`nodes.txt`**: Output of `kubectl get nodes -o wide`.
- **`nodes.yaml`**: Output of `kubectl get nodes -o yaml`.
- **`version.yaml`**: Output of `kubectl version --output=yaml`.

### 2. ConfigMaps (`configmaps/`)

Configuration details for the SCC operator.

- **`configmaps-list.txt`**: A list of all ConfigMaps in the operator's namespace.
- **`scc-operator-config.yaml`**: The main configuration for the operator from the `scc-operator-config` ConfigMap.

### 3. Custom Resource Definitions (`crds/`)

The definition of the `Registration` Custom Resource.

- **`registrations.scc.cattle.io.yaml`**: The YAML definition of the `registrations.scc.cattle.io` CRD.
- **`registrations.scc.cattle.io-describe.txt`**: The output of `kubectl describe crd registrations.scc.cattle.io`.

### 4. Events (`events/`)

Kubernetes events to provide a timeline of recent activities.

- **`events-<operator-namespace>.txt`**: Events from the SCC operator's namespace.
- **`events-<lease-namespace>.txt`**: Events from the lease namespace (if different from the operator namespace).
- **`events-all-namespaces.txt`**: Events from all namespaces for broader context.

### 5. Leases (`leases/`)

Information about the leader election lease for the operator.

- **`leases-list.txt`**: A list of all leases in the lease namespace.
- **`lease-<operator-name>.yaml`**: The YAML definition of the operator's lease object.
- **`lease-<operator-name>-describe.txt`**: The output of `kubectl describe lease <operator-name>`.

### 6. Operator Pods (`operator-pods/`)

Detailed information about the SCC operator pods.

- **`pods-list.txt`**: A list of all pods in the operator's namespace.
- **`pod-<pod-name>.yaml`**: The YAML definition for each operator pod.
- **`pod-<pod-name>-describe.txt`**: The output of `kubectl describe pod` for each operator pod.
- **`pod-<pod-name>-logs.txt`**: Current logs from all containers in each operator pod.
- **`pod-<pod-name>-logs-previous.txt`**: Logs from previous container instances in each operator pod (if any).
- **`no-pods.txt`**: This file is created if no operator pods are found.

### 7. Registrations (`registrations/`)

Information about the `Registration` custom resources.

- **`registrations-list.txt`**: A list of all `Registration` resources in the cluster.
- **`registration-<reg-name>.yaml`**: The YAML definition for each `Registration` resource.
- **`registration-<reg-name>-describe.txt`**: The output of `kubectl describe registration` for each resource.
- **`no-registrations.txt`**: This file is created if no `Registration` resources are found.

### 8. Secrets (`secrets/`)

Secrets related to SCC registration and credentials. **Sensitive data fields are redacted by default.**

- **`secrets-list.txt`**: A list of all secrets in the operator's namespace.
- **`secret-<secret-name>.yaml`**: The YAML definition for each collected secret. The following secret patterns are collected:
    - `scc-registration`
    - `rancher-registration`
    - `scc-system-credentials-*`
    - `registration-code-*`
    - `offline-request-*`
    - `offline-certificate-*`
    - `rancher-scc-metrics`
- **`REDACTED.txt`**: A note indicating that secret data has been redacted.
- **`UNREDACTED-WARNING.txt`**: A warning file present if the `--no-redact` flag was used.

### 9. Metadata (`metadata.txt`)

A summary of the collection process and environment.

- Collection timestamp.
- Bundle name and configuration.
- Kubernetes version and context.
- A summary of collected resources.
- A security warning if redaction was disabled.
