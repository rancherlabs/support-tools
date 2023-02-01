# Rancher v2.x logs-collector

## Notes

This script is intended to collect logs from:
- [Rancher Kubernetes Engine (RKE) CLI](https://rancher.com/docs/rke/latest/en/) provisioned clusters
- [K3s clusters](https://rancher.com/docs/k3s/latest/en/)
- [RKE2 clusters](https://docs.rke2.io/)
- Rancher provisioned [Custom](https://docs.ranchermanager.rancher.io/pages-for-subheaders/use-existing-nodes)
- [Node Driver](https://docs.ranchermanager.rancher.io/pages-for-subheaders/use-new-nodes-in-an-infra-provider) clusters
- [Kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) clusters has been also recently added.


This script may not collect all necessary information when run on nodes in Hosted [Kubernetes Provider clusters](https://docs.ranchermanager.rancher.io/pages-for-subheaders/set-up-clusters-from-hosted-kubernetes-providers).

Output will be written to `/tmp` as a tar.gz archive named `<hostname>-<date>.tar.gz`, the default output directory can be changed with the `-d` flag.

## Usage

The script needs to be downloaded and run directly on the node, using the `root` user or `sudo`.

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
  > Note: This command requires `curl` to be installed, and internet access from the node.

## Flags

```
Rancher 2.x logs-collector
  Usage: rancher2_logs_collector.sh [ -d <directory> -s <days> -e <days> -r <k8s distribution> -p -f ]

  All flags are optional

  -c    Custom data-dir for RKE2 (ex: -c /opt/rke2)
  -d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
  -s    Start day of journald and docker log collection, # of days relative to the current day (ex: -s 7)
  -e    End day of journald and docker log collection, # of days relative to the current day (ex: -e 5)
  -r    Override k8s distribution if not automatically detected (rke|k3s|rke2|kubeadm)
  -p    When supplied runs with the default nice/ionice priorities, otherwise use the lowest priorities
  -f    Force log collection if the minimum space isn't available
```
