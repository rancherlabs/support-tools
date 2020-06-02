# rancher-windows-log-collector
Windows log collector for Rancher Windows Worker Nodes


## How To Run the Script

```ps1
Set-ExecutionPolicy Bypass
Start-BitsTransfer https://raw.githubusercontent.com/rosskirkpat/rancher-windows-log-collector/master/log-collect-beta.ps1
.\log-collect-beta.ps1
```

### Expected output
#### Note: The `Unable to Collect Windows Firewall information` error is expected if it there are not Domain specific firewall rules pushed out by the customer

```ps1
 .\log-collect-beta.ps1
Running Rancher Log Collection
Creating temporary directory
OK
Collecting System information
OK
Collecting PS output
Collecting Disk information
Collecting Volume info
OK
Collecting Windows Firewall info
Collecting Rules for Domain profile
get_firewall_info : Unable to Collect Windows Firewall information
At C:\Users\Administrator\log-collect-beta.ps1:397 char:5
+     get_firewall_info
+     ~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (:) [Write-Error], WriteErrorException
    + FullyQualifiedErrorId : Microsoft.PowerShell.Commands.WriteErrorException,get_firewall_info

Collecting installed applications list
OK
Collecting Services list
OK
Collecting Docker daemon information
OK
Collecting Kubernetes components config
OK
Collecting Windows Event logs
OK
Collecting Kubernetes Logs
OK
Collecting network Information
OK
Collecting group policy information
Get-GPOReport is not a valid cmdlet
Collecting proxy information
OK
Archiving Rancher log collection script data
OK
Done. Your log bundle is located in  C:\rancher\rancher_EC2AMAZ-ENEJ0H8_20200602T1704290242Z
Please supply the log bundle(s) to Rancher Support
Cleaning up directory
OK
```
