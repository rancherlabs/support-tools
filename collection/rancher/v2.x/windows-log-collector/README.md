# rancher-windows-log-collector
Windows log collector for Rancher Windows Worker Nodes


## How To Run the Script

- Open a new Powershell window with Administrator Privileges (Find Windows Powershell in Start Menu, right click, Run As Administrator)
- run the following commands in your Powershell window

```ps1
Set-ExecutionPolicy Bypass
Start-BitsTransfer https://raw.githubusercontent.com/rancherlabs/support-tools/windows-log-collect/collection/rancher/v2.x/windows-log-collector/win-log-collect.ps1
.\win-log-collect.ps1
```

### Upon successful completion, your log bundle will be on the root of the C: drive (example below)

`dir C:\`
```
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
-a----         6/2/2020   5:07 PM         428911 rancher_EC2AMAZ-ENEJ0H8_20200602T1704290242Z.tgz
```

### Expected output
#### Note: The `Unable to Collect Windows Firewall information` error is expected if it there are not Domain specific firewall rules pushed out by the customer

```ps1
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
Done. Your log bundle is located in  C:\rancher_EC2AMAZ-ENEJ0H8_20200602T1704290242Z
Please supply the log bundle(s) to Rancher Support
Cleaning up directory
OK
```
