# Rancher v2.x Windows log-collector

This logs collector project was created to collect logs from Windows Kubernetes nodes. It is designed to be used with RKE2 Windows worker nodes for troubleshooting support cases.

## Usage

- Open a new PowerShell window with Administrator Privileges (Find Windows PowerShell in Start Menu, right click, Run As Administrator)
- Run the following commands in your PowerShell window

```ps1
Set-ExecutionPolicy Bypass
Start-BitsTransfer https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/windows-log-collector/win-log-collect-rke2.ps1
.\win-log-collect-rke2.ps1
```

### Upon successful completion, your log bundle will be on the root of the C: drive (example below)

```
> dir C:\
d-----       11/14/2018   6:56 AM                EFI
d-----         6/2/2020   3:31 PM                etc
d-----         6/2/2020   3:31 PM                opt
d-----        5/13/2020   6:03 PM                PerfLogs
d-r---        5/13/2020   5:25 PM                Program Files
d-----         6/2/2020   3:16 PM                Program Files (x86)
d-----         6/2/2020   7:23 PM                rancher
d-----         6/2/2020   4:06 PM                run
d-r---         6/1/2020   6:30 PM                Users
d-----         6/2/2020   3:31 PM                var
d-----         6/1/2020   6:26 PM                Windows
-a----         6/2/2020   5:07 PM         270086 rancher_rke2_node_host_2026-08-12_14_55_00.tar.gz
```

### Expected output

> Note: The `Get-GPOReport is not a valid cmdlet` message can be expected on hosts that do not have GroupPolicy tooling installed.
>
> Note: The `Path not found, skipping: C:\etc\rancher\rke2\config.yaml`, `config.yml`, or `config.yaml.d\*.yml` warnings are expected when the node is running with default RKE2 settings and no local override files are present in those paths.

```ps1
Validating Windows host prefix path
Validating Windows host prefix path - OK
Running Rancher RKE2 Log Collection
Creating temporary directory
Creating temporary directory - OK
Collecting System information
Collecting System information - OK
Configuring environment for RKE2 tooling
Configuring environment for RKE2 tooling - OK
Collecting PS output
Collecting PS output - OK
Collecting Disk and Volume information
Collecting Disk and Volume information - OK
Collecting Windows Firewall info
get_firewall_info : Unable to Collect Windows Firewall information
At C:\Users\Administrator\lwin-lod-collect-rke2.ps1:237 char:5
+     get_firewall_info
+     ~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (:) [Write-Error], WriteErrorException
    + FullyQualifiedErrorId : Microsoft.PowerShell.Commands.WriteErrorException,get_firewall_info

Collecting Services list
Collecting Services list - OK
Collecting RKE2 core service status (rke2, rancher-wins, csiproxy)
Collecting RKE2 core service status - OK
Collecting containerd runtime information
Collecting containerd runtime information - OK
Collecting Kubernetes/RKE2 components config
WARNING: Path not found, skipping: C:\etc\rancher\rke2\config.yaml
WARNING: Path not found, skipping: C:\etc\rancher\rke2\config.yml
WARNING: Path not found, skipping: C:\etc\rancher\rke2\config.yaml.d\*.yml
Collecting Kubernetes/RKE2 components config - OK
Collecting certificates for RKE2
Collecting certificates for RKE2 - OK
Collecting Windows Event logs
Collecting Windows Event logs - OK
Collecting RKE2 agent component logs (kubelet, kube-proxy, rke2)
Collecting RKE2 agent component logs - OK
Collecting Kubernetes container logs via crictl
No containers found in namespace 'kube-system', skipping
No containers found in namespace 'cattle-system', skipping
No containers found in namespace 'cattle-fleet-system', skipping
No containers found in namespace 'cattle-fleet-local-system', skipping
No containers found in namespace 'ingress-nginx', skipping
No containers found in namespace 'cattle-monitoring-system', skipping
Collecting Kubernetes container logs via crictl - OK
Collecting rancher-wins service information
Collecting rancher-wins service information - OK
Collecting csiproxy service information
Collecting csiproxy service information - OK
Collecting network Information
Collecting network Information - OK
Collecting group policy information
Get-GPOReport is not a valid cmdlet
Collecting proxy information
Collecting proxy information - OK
Archiving Rancher RKE2 log collection script data
Archiving Rancher RKE2 log collection script data - OK
Your log bundle is located in  C:\\rancher_rke2_node_host_2026-08-12_14_55_00.tar.gz
Please supply the log bundle(s) to Rancher Support
Cleaning up temporary directory
Cleaning up temporary directory - OK
```
