# Rancher v2.x profiles-collector

## Notes

This script is intended to collect:
- [Golang profiles](https://github.com/pkg/profile) for [Rancher Manager](https://github.com/rancher/rancher/), and Rancher Cluster Agent
- Rancher debug logs
- Rancher audit logs when available
- Events from the cattle-system namespace
- metrics with kubectl top from pods and nodes


Output will be written to `/tmp` as a tar.gz archive named `<pod-name>-<date>.tar.gz`

## Usage

The script needs to be downloaded and run with a kubeconfig file pointed to the local Rancher cluster or a downstream cluster where cattle-cluster-agent pods are running

### Download and run the script
* Save the script as: `continuous_profiling.sh`

  Using `wget`:
    ```bash
    wget https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/profile-collector/continuous_profiling.sh
    ```
  Using `curl`:
    ```bash
    curl -OLs https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/profile-collector/continuous_profiling.sh
    ```
 
* Run the script:
  ```bash
  sudo bash continuous_profiling.sh
  ```
  The script will run until it receives a SIGKILL (Ctrl-C)
## Flags

```
Rancher 2.x profile-collector
  Usage: profile-collector.sh [-a rancher -p goroutine,heap ]

  All flags are optional

  -a    Application, either rancher or cattle-cluster-agent
  -p    Profiles to be collected (comma separated): goroutine,heap,threadcreate,block,mutex,profile
  -s    Sleep time between loops in seconds
  -t    Time of CPU profile collections
  -h    This help
```
