# Rancher v2.x logs-collector

This logs collector project was created to collect logs from Linux Kubernetes nodes. It is designed to be used in the following environments for troubleshooting support cases:
- [RKE2 clusters](https://docs.rke2.io/)
- [RKE1 clusters](https://rancher.com/docs/rke/latest/en/)
- [K3s clusters](https://docs.k3s.io/)
- [Custom clusters](https://docs.ranchermanager.rancher.io/pages-for-subheaders/use-existing-nodes)
- [Infrastructure provider clusters](https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/launch-kubernetes-with-rancher/use-new-nodes-in-an-infra-provider)
- [Kubeadm clusters](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)

> Note: This script may not collect all necessary information when run on nodes in a [Hosted Kubernetes Provider](https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/kubernetes-clusters-in-rancher-setup/set-up-clusters-from-hosted-kubernetes-providers) cluster.

## Table of Contents

- [Usage](#usage)
  - [Download and run the script](#download-and-run-the-script)
  - [Optional: Download and run the script in one command](#optional-download-and-run-the-script-in-one-command)
  - [Optional: Run the script from a pod](#optional-run-the-script-from-a-pod)
  - [Optional: Run the script with kubectl debug](#optional-run-the-script-with-kubectl-debug)
    - [Using the `rancherlabs/swiss-army-knife` container image](#using-the-rancherlabsswiss-army-knife-container-image)
    - [Alternatively: Using another container image](#alternatively-using-another-container-image)
- [Flags](#flags)
- [Scope of collection](#scope-of-collection)

## Usage

The script needs to be downloaded and run directly on the node, using the `root` user or `sudo`.

Output will be written to `/tmp` as a tar.gz archive named `<hostname>-<date>.tar.gz`, the default output directory can be changed with the `-d` flag.

### Download and run the script
* Save the script as: `rancher2_logs_collector.sh`

  Using `wget`:
    ```bash
    wget --backups https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/logs-collector/rancher2_logs_collector.sh
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

### Optional: Run the script from a pod
  - Deploy the log collector pod:
  ```bash
  kubectl apply -f https://raw.githubusercontent.com/rancherlabs/support-tools/refs/heads/master/collection/rancher/v2.x/logs-collector/logs_collector.yaml

  kubectl exec -it rancher-logs-collector -- bash /usr/local/bin/rancher2_logs_collector.sh
  ```

  - Copy the collection from the pod using the "kubectl cp" command example in the output

  - Clean up the log collector pod
  ```bash
  kubectl delete -f https://raw.githubusercontent.com/rancherlabs/support-tools/refs/heads/master/collection/rancher/v2.x/logs-collector/logs_collector.yaml
  ```

  > Note: When run from a pod the log collection only captures Kubernetes-specific output. To collect OS or node-level output, run the logs collector directly on a node.

### Optional: Run the script with kubectl debug

If you do not have direct SSH access to a node but need to collect OS or node-level output (such as OS and container runtime logs), you can use the `kubectl debug` command to schedule an ephemeral pod on a node and run the logs collector.

- Set the target node name as a variable:
  ```bash
  export NODE_NAME="<your-node-name>"
  ```

- Start the debug pod on the node:

The script will re-execute in a chroot environment and generate a `.tar.gz` archive. The logs collector pod will sleep for 1 day to keep the pod running to provide access to the pod logs and copying the archive file.

  #### Using the `rancherlabs/swiss-army-knife` container image
  - Start a debug session on the node, and execute the logs collector with the `-D` flag:
    ```bash
    kubectl debug node/${NODE_NAME} --attach=false --image=rancherlabs/swiss-army-knife -- bash -c "rancher2_logs_collector.sh -D"
    ```

  #### Alternatively: Using another container image
  - Start a debug session on the node, and execute the logs collector with the `-D` flag:
    ```bash
    export IMAGE="<container-image>"
    ```
    ```bash
    kubectl debug node/${NODE_NAME} --attach=false --image=${IMAGE} -- bash -c "curl -OLs https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/logs-collector/rancher2_logs_collector.sh && bash rancher2_logs_collector.sh -D"
    ```

    > **Note** This approach requires `curl` to be installed and internet access to download the script

- To view the logs and download the archive, copy the name of the debug pod that was just created, set the variable and use the pod name in the command examples below:
  ```bash
  POD_NAME=<node-debugger-pod-name-here>
  ```
  ```bash
  kubectl logs -f $POD_NAME
  ```

- Once finished, copy the logs from the pod using the example command in the pod logs.

- Clean up the debug pod when finished:
  ```bash
  kubectl delete pod $POD_NAME
  ```

## Flags

```
Rancher 2.x logs-collector
  Usage: rancher2_logs_collector.sh [ -d <directory> -s <days> -e <days> -r <k8s distribution> -p -f ]

  All flags are optional

  -c    Custom data-dir for RKE2 (ex: -c /opt/rke2)
  -d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
  -s    Start day of journald and docker log collection, # of days relative to the current day (ex: -s 7)
  -e    End day of journald and docker log collection, # of days relative to the current day (ex: -e 5)
  -S    Start date of journald and docker log collection. (ex: -S 2022-12-05)
  -E    End date of journald and docker log collection. (ex: -E 2022-12-07)
  -r    Override k8s distribution if not automatically detected (rke|k3s|rke2|kubeadm)
  -p    When supplied runs with the default nice/ionice priorities, otherwise use the lowest priorities
  -f    Force log collection if the minimum space isn't available
  -o    Obfuscate IP addresses and hostnames
```

## Scope of collection

Collection includes the following areas, the logs collector is designed to gather necessary diagnostic information while respecting privacy and security concerns. A detailed list is maintained in [collection-details.md](./collection-details.md).

- Related OS logs and configuration:  
  - Network configuration - interfaces, iptables
  - Disk configuration - devices, filesystems, utilization
  - Performance - resource usage, tuning 
  - OS release and logs - versions, messages/syslog
- Related Kubernetes object output, kubectl commands, and pod logs
  - Related CRD objects
  - Output from kubectl for troubleshooting
  - Pod logs from related namespaces

The scope of collection is intentionally limited to avoid sensitive data, use minimal resources and disk space, and focus on the core areas needed for troubleshooting.

IP addresses and hostnames are collected and can assist with troubleshooting, however these can be obfuscated when adding the `-o` flag for the log collection script.

Note, if additional verbosity, debug, or audit logging is enabled for the related Kubernetes and OS components, these logs can be included and may contain sensitive output. 
