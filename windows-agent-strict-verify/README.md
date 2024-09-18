# Enabling agent strict TLS verification on existing Windows nodes

In certain conditions, Windows nodes will not respect the Agent TLS Mode value set on the Rancher server. This setting was implemented in Rancher 2.9.0 and 2.8.6

Windows nodes will not respect this setting if the following two conditions are true

1. The node was provisioned using a Rancher version older than 2.9.2 or 2.8.8, and continues to be used after a Rancher upgrade to 2.9.2, 2.8.8, or greater
2. The node is running a version of rke2 _older_ than the August 2024 patches. (i.e. any version _lower_ than v1.30.4, v1.29.8, v1.28.13, v1.27.16.)

## Workaround

In order to retroactively enable strict TLS verification on Windows nodes, the following process must be followed. A Powershell script, `update-node.ps1` has been included to automate some parts of this process, however some steps (such as retrieving the required credentials used by the script) must be done manually. 


This process needs to be repeated for each Windows node joined to the cluster, but does not need to be done for newly provisioned nodes after Rancher has been upgraded to at least 2.9.2 or 2.8.8 - even if the rke2 version is older than the August patches. In scenarios where it is possible / safe to reprovision the impacted Windows nodes, this process may not be needed. 

1. Stop the `rancher-wins` service using the `Stop-Service` PowerShell Command (`Stop-Service rancher-wins`)

2. Update the version of `wins.exe` running on the node. This can either be done manually, or via the `update-node.ps1` PowerShell script by passing the `-DownloadWins` flag
    1. If a manual approach is taken, download the latest [version of rancher-wins from GitHub](https://github.com/rancher/wins/releases) (at least version `0.4.18`) and place the updated binary in the `c:/usr/local/bin` and `c:/Windows` directories, replacing the existing binaries.

    2. If the automatic approach is taken, then you must include the `-DownloadWins` flag when invoking `update-node.ps1`. The version of `rancher-wins` packaged within your Rancher server will then be downloaded.
        + You must ensure that you are running a version of Rancher which embeds at _least_ `rancher-wins` `v0.4.18`. This version is included in Rancher v2.9.2, v2.8.8, and above.
        + Refer to the [`Obtaining the CATTLE_TOKEN and CATTLE_SERVER variables`](#obtaining-the-cattle_token-and-cattle_server-variables) section below to retrieve the required `CATTLE_TOKEN` and `CATTLE_SERVER` variables.

3. Manually update the `rancher-wins` config file to enable strict tls verification
    1. This file is located in `c:/etc/rancher/wins/config`.
        1. At the root level (i.e. a new line just before the `system-agent` field) add the following value `agentStrictTLSMode: true`
        2. An [example configuration file](#example-updated-wins-config-file) can be seen at the bottom of this file 

4. If needed, regenerate the rancher connection file
    1. To determine if you need to do this, look at the `/var/lib/rancher/agent/rancher2_connection_info.json` file. If you intend to use strict validation, this file must contain a valid `ca-certificate-data` field.
    2. If this field is missing
        1. Refer to the [`Obtaining the CATTLE_TOKEN and CATTLE_SERVER variables`](#obtaining-the-cattle_token-and-cattle_server-variables) section to retrieve the required `CATTLE_TOKEN` and `CATTLE_SERVER` parameters
        2. Create a new file containing the `update-node.ps1` script and run it, ensuring you properly pass the `CATTLE_SERVER` value to the `-RancherServerURL` flag, and the `CATTLE_TOKEN` value to the `-Token` flag.
           1. Depending on whether you wish to manually update `rancher-wins`, run one of the following two commands
              1. `./update-node.ps1 -RancherServerURL $CATTLE_SERVER -Token $CATTLE_TOKEN`
              2. `./update-node.ps1 -RancherServerURL $CATTLE_SERVER -Token $CATTLE_TOKEN -DownloadWins`
           2. Confirm that the `rancher2_connection_info.json` file contains the correct CA data.

5. Confirm the proper version of `rancher-wins` has been installed by running `win.exe --version`
6. Restart the node (`Restart-Computer`). 
   1. If the node is running an RKE2 version older than the August patches, you **must** restart the node otherwise pod networking will be impacted. 

### Obtaining the `CATTLE_TOKEN` and `CATTLE_SERVER` variables

- You must be a cluster administrator or have an account permitted to view cluster secrets in order to use this script, as the `CATTLE_TOKEN` is stored in a Kubernetes secret. You cannot simply generate an API token using the Rancher UI. 
- To obtain the `CATTLE_TOKEN` and `CATTLE_SERVER` values using the Rancher UI
  1. Open Rancher's Cluster Explorer UI for the cluster which contains the relevant Windows nodes. 
  2. In the left hand section, under `More Resources`, go to `Core`, and then finally, `Secrets`. 
  3. Find the secret named `stv-aggregation`, and copy the `CATTLE_SERVER` and `CATTLE_TOKEN` fields. 
  4. Pass `CATTLE_TOKEN` to the `-Token` flag, and `CATTLE_SERVER` to the `-RancherServerURL` flag.
- To obtain the `CATTLE_TOKEN` and `CATTLE_SERVER` values using kubectl 
  1. `kubectl get secret -n cattle-system stv-aggregation --template={{.data.CATTLE_TOKEN}} | base64 -d`
  2. `kubectl get secret -n cattle-system stv-aggregation --template={{.data.CATTLE_SERVER}} | base64 -d`

### Example updated wins config file

```yaml
# This file is located at c:/etc/rancher/wins/config
white_list:
  processPaths:
    - C:/etc/rancher/wins/powershell.exe
    - C:/etc/rancher/wins/wins-upgrade.exe
    - C:/etc/wmi-exporter/wmi-exporter.exe
    - C:/etc/windows-exporter/windows-exporter.exe
  proxyPorts:
    - 9796
agentStrictTLSMode: true
systemagent:
  workDirectory: C:/var/lib/rancher/agent/work
  appliedPlanDirectory: C:/var/lib/rancher/agent/applied
  remoteEnabled: true
  preserveWorkDirectory: false
  connectionInfoFile: C:/var/lib/rancher/agent/rancher2_connection_info.json
csi-proxy:
  url: https://haffel-rancher.cp-dev.rancher.space/assets/csi-proxy-%[1]s.tar.gz
  version: v1.1.3
  kubeletPath: C:/bin/kubelet.exe
```