# Rancher v2.x profiles-collector

This profiles collector project was created to collect:
- [Golang profiles](https://github.com/pkg/profile) for [Rancher Manager](https://github.com/rancher/rancher/), Rancher Cluster Agent, Fleet Controller and Fleet Agent
- Rancher debug or trace logs when collecting Rancher profiles
- Rancher audit logs when available
- Events from the cattle-system namespace
- metrics with kubectl top from pods and nodes
- Rancher metrics exposed on <RANCHER_URL>/metrics

## Usage

The script needs to be downloaded and run with a kubeconfig file for the Rancher Management (local) cluster, or a downstream cluster where cattle-cluster-agent pods are running

### Download and run the script
- Save the script as: `continuous_profiling.sh`

  Using `wget`:
    ```bash
    wget https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/profile-collector/continuous_profiling.sh
    ```
  Using `curl`:
    ```bash
    curl -OLs https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/profile-collector/continuous_profiling.sh
    ```
 
- Run the script:
  ```bash
  bash continuous_profiling.sh
  ```
  The script will run until it receives a SIGKILL (Ctrl-C)
  A tarball will be generated at the same folder where the script is running. Please share that file with Rancher support.

## Flags

```
Rancher 2.x profile-collector
  Usage: profile-collector.sh [-a rancher -p goroutine,heap ]

  All flags are optional

  -a    Application, rancher, cattle-cluster-agent, fleet-controller, fleet-agent
  -p    Profiles to be collected (comma separated): goroutine,heap,threadcreate,block,mutex,profile
  -s    Sleep time between loops in seconds
  -t    Time of CPU profile collections
  -l    Log level of the Rancher pods: debug or trace
  -h    This help
```

## Examples
- The default collection is equivalent of:
  ```bash continuous_profiling -a rancher -p goroutine,heap,profile -s 120 -t 30```

- Collecting Upstream Rancher profiles every 30 minutes, and collect trace level logs
  ```bash continuous_profiling -s 1800 -l trace```

- Collecting cattle-cluster-agent heap and profile
  ```bash continuous_profiling -a cattle-cluster-agent -p heap,profile ```

- Collecting fleet-agent profile profile (cpu) over a minute
  ```bash continuous_profiling -a fleet-agent -t 60```
