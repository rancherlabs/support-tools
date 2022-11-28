# Rancher v2.x logs-collector

## Notes

This script is intended to collect logs from RKE, k3s and RKE2 cluster nodes provisioned by Rancher, or provisioned directly. When used on a node provisioned by another Kubernetes distribution, some necessary information may not be included.

Access to the node using the root user, or sudo is required.

By default the output will be written to `/tmp` as a tar.gz archive named `<hostname>-<date>.tar.gz`, the default output directory can be changed with the `-d` flag.

## How to use

### Download and run the script
* Save the script as: `rancher2_logs_collector.sh`

  Using `wget`:
    ```bash
    wget https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/logs-collector/rancher2_logs_collector.sh
    ```
  Using `curl`:
    ```bash
    curl -OLs https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/logs-collector/rancher2_logs_collector.sh
    ```
 
* Run the script:
  ```bash
  sudo bash rancher2_logs_collector.sh
  ```
### Optional: Download and run the script in one command
  ```bash
  curl -Ls rnch.io/rancher2_logs | sudo bash
  ```

## Flags

```
Rancher 2.x logs-collector
  Usage: rancher2_logs_collector.sh [ -d <directory> -s <days> -r <k8s distribution> -p -f ]

  All flags are optional

  -c    Custom data-dir for RKE2 (ex: -c /opt/rke2)
  -d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
  -s    Number of days history to collect from container and journald logs (ex: -s 7)
  -r    Override k8s distribution if not automatically detected (rke|k3s|rke2)
  -p    When supplied runs with the default nice/ionice priorities, otherwise use the lowest priorities
  -f    Force log collection if the minimum space isn't available
```
