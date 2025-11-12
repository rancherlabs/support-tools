# SCC Operator Support Bundle Collector & Analyzer

This directory contains two scripts for troubleshooting the SUSE Customer Center (SCC) Operator in a Rancher environment:
1.  `scc-operator-collector.sh`: Gathers diagnostic information from the cluster.
2.  `analyzer.sh`: Processes the collected bundle for easier local analysis.

---

## Collector (`scc-operator-collector.sh`)

This script collects various details about the operator, its custom resources, and the Kubernetes environment it runs in.

### How to Run the Collector

The script can be run directly from your local machine, provided you have `kubectl` installed and configured to connect to the target Kubernetes cluster.
If run on a k8s cluster node, the script only needs to be run on a single node as results should not vary per-node.

#### Prerequisites

- `kubectl` installed and configured with access to the Rancher `local` cluster.

#### Execution

1.  **Download the script:**
    -   Using `wget`:
        ```bash
        wget https://raw.githubusercontent.com/rancherlabs/support-tools/refs/heads/master/collection/rancher/v2.x/scc-operator-collector/scc-operator-collector.sh
        ```
    -   Using `curl`:
        ```bash
        curl -O https://raw.githubusercontent.com/rancherlabs/support-tools/refs/heads/master/collection/rancher/v2.x/scc-operator-collector/scc-operator-collector.sh
        ```

2.  **Run the collector:**
    ```bash
    bash scc-operator-collector.sh
    ```
    This will create a compressed `tar.gz` archive named `scc-support-bundle-<timestamp>.tar.gz` in the current directory. This bundle is safe to share with SUSE support.

### Collector Command-line Options

| Option | Description | Default |
| --- | --- | --- |
| `--no-redact` | Disable redaction of sensitive information in secrets. **WARNING:** The bundle will contain sensitive data. | `false` |
| `--output <format>` | Output format. Can be `tar` (a `tar.gz` archive) or `folder` (a directory). | `tar` |
| `--namespace <ns>` | The namespace where the SCC Operator is running. | `cattle-scc-system` |
| `--lease-namespace <ns>`| The namespace where the operator's leader election lease is stored. | `kube-system` |
| `--name <name>` | A custom name for the support bundle. | `scc-support-bundle-<timestamp>`|
| `-h`, `--help` | Show the help message. | |

#### Examples

-   **Default collection (redacted, compressed archive):**
    ```bash
    bash scc-operator-collector.sh
    ```

-   **Collect into a folder for local inspection:**
    ```bash
    bash scc-operator-collector.sh --output folder
    ```

-   **Collect without redacting secrets (for local debugging only):**
    ```bash
    bash scc-operator-collector.sh --no-redact
    ```
    *Note: This forces the output to `folder` format for security reasons.*

### Security and Redaction

By default, the collector redacts sensitive data within secrets to prevent accidental exposure of credentials. When the `--no-redact` flag is used, this redaction is skipped.

**WARNING:** Bundles created with `--no-redact` contain sensitive credentials and should **NEVER** be shared or uploaded to support tickets. Use the `analyzer.sh` script for local debugging of unredacted bundles.

### What is Collected?

For a detailed list of the information gathered by the collector, please see [collection-details.md](./collection-details.md).

---

## Analyzer (`analyzer.sh`)

This script processes a support bundle created by the collector, making it easier to read for local debugging. Its primary function is to decode secrets into a human-readable format.

### How to Run the Analyzer

The analyzer is designed to be run on a workstation against a support bundle that has been unarchived or collected using the `folder` output format.

#### Prerequisites

-   `jq` installed.
-   `yq` installed.
-   A support bundle directory (not a `.tar.gz` file).

#### Execution

1.  **Download the script:**
    -   Using `wget`:
        ```bash
        wget https://raw.githubusercontent.com/rancher/support-tools/master/collection/rancher/v2.x/scc-operator-collector/analyzer.sh
        ```
    -   Using `curl`:
        ```bash
        curl -O https://raw.githubusercontent.com/rancher/support-tools/master/collection/rancher/v2.x/scc-operator-collector/analyzer.sh
        ```

2.  **Run the analyzer against a bundle directory:**
    ```bash
    bash analyzer.sh scc-support-bundle-<timestamp>
    ```

### What the Analyzer Does

The script creates a new `processed-secrets` directory inside the bundle directory. Within this new directory, it:
-   Decodes all `data` fields from secrets and displays them as human-readable `stringData`.
-   For the `rancher-scc-metrics` secret, it pretty-prints the JSON `payload` for easier review.

This allows you to easily inspect secret contents without manual `base64` decoding, which is especially useful when reviewing bundles locally.
