# SCC Operator Support Bundle Collector

This script collects diagnostic information for troubleshooting the SUSE Customer Center (SCC) Operator in a Rancher environment. It gathers various details about the operator, its custom resources, and the Kubernetes environment it runs in.

## How to Run

The script can be run directly from your local machine, provided you have `kubectl` installed and configured to connect to the target Kubernetes cluster.

### Prerequisites

- `kubectl` installed and configured (for Admin access to the Rancher `local` cluster)
- `yq` and `jq` are recommended for more specific secret redaction. If not present, redaction will be more aggressive.

### Execution

To run the collector with default settings:

```bash
./scc-operator-collector.sh
```

This will create a compressed `tar.gz` archive named `scc-support-bundle-<timestamp>.tar.gz` in the current directory.

### Command-line Options

The script accepts several options to customize its behavior:

| Option                   | Description                                                                                                                                 | Default                          |
|--------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------|
| `--no-redact`            | Disable redaction of sensitive information in secrets. **WARNING:** The bundle will contain sensitive data. (Intended for local debug only) | `false`                          |
| `--output <format>`      | Output format. Can be `tar` (a `tar.gz` archive) or `folder` (a directory).                                                                 | `tar`                            |
| `--namespace <ns>`       | The namespace where the SCC Operator is running.                                                                                            | `cattle-scc-system`              |
| `--lease-namespace <ns>` | The namespace where the operator's leader election lease is stored.                                                                         | `kube-system`                    |
| `--name <name>`          | A custom name for the support bundle.                                                                                                       | `scc-support-bundle-<timestamp>` |
| `-h`, `--help`           | Show the help message.                                                                                                                      |                                  |

#### Examples

- **Default collection:**
  ```bash
  ./scc-operator-collector.sh
  ```

- **Collect into a folder for local inspection:**
  ```bash
  ./scc-operator-collector.sh --output folder
  ```

- **Collect without redacting secrets (for local debugging only):**
  ```bash
  ./scc-operator-collector.sh --no-redact
  ```
  *Note: This will force the output to `folder` format for security reasons.*

- **Collect from a custom namespace:**
  ```bash
  ./scc-operator-collector.sh --namespace my-scc-operator
  ```

## What is Collected?

For a detailed list of the information collected by this script, please see [collection-details.md](./collection-details.md).

## Security and Redaction

By default, the script redacts sensitive information within secrets to prevent accidental exposure of credentials. The following fields are redacted:

- `regCode` in `scc-registration` and `registration-code-*` secrets.
- `password` in `scc-system-credentials-*` secrets.

When the `--no-redact` flag is used, this redaction is disabled. For security, using `--no-redact` will force the output to be a `folder` and not a `tar.gz` archive. This is to discourage sharing unredacted bundles.

**WARNING:** Bundles created with `--no-redact` contain sensitive credentials and should **NEVER** be shared or uploaded to support tickets.
