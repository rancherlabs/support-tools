<# 
.SYNOPSIS 
    Collects Rancher logs from Windows Worker Nodes 

.DESCRIPTION 
    Run the script to gather troubleshooting information on the OS, Docker, network, system, and grab all relevant logs. 

.NOTES
    This script needs to be run with Elevated permissions to allow for the complete collection of information.
    Once the script has completed, please supply the .tar.gz file to Rancher Support.

.EXAMPLE 
    rancher-win-log-collector.ps1
    Gather troubleshooting information on the OS, Docker, network, system, and grab all relevant logs.
#>

# set utf8 as PS defaults to utf16
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# options
$basedir = "C:\rancher"
$directory = "$basedir\log-collector"
$currenttime = Get-Date -Format FileDateTimeUniversal
#$currenttime = get-date -Format yyyy-MM-dd
$outfilename = "rancher_" + "$(hostname)" + "_" + $currenttime

# init functions
# ---------------------------------------------------------------------------------------

Function is_elevated{
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-warning "This script requires elevated privileges."
        Write-Host "Please re-launch as Administrator." -foreground "red" -background "black"
        Break
    }
}

function Check-Command($cmdname)
{
    return [bool](Get-Command -Name $cmdname -ErrorAction SilentlyContinue)
}

Function create_working_dir{
    try {
        Write-Host "Creating temporary directory"
        New-Item -ItemType Directory -Path "$directory" -Force >$null
        New-Item -ItemType Directory -Path "$directory/containerlogs" -Force >$null
        New-Item -ItemType Directory -Path "$directory/containerlogs/rke" -Force >$null
        New-Item -ItemType Directory -Path "$directory/podlogs" -Force >$null
        New-Item -ItemType Directory -Path "$directory/nginx" -Force >$null
        New-Item -ItemType Directory -Path "$directory/nginx/logs" -Force >$null
        New-Item -ItemType Directory -Path "$directory/config" -Force >$null
        New-Item -ItemType Directory -Path "$directory/config/cni" -Force >$null
        New-Item -ItemType Directory -Path "$directory/config/cni/networks" -Force >$null
        New-Item -ItemType Directory -Path "$directory/config/cni/flannel" -Force >$null
        New-Item -ItemType Directory -Path "$directory/config/wins" -Force >$null
        New-Item -ItemType Directory -Path "$directory/config/flannel" -Force >$null
        New-Item -ItemType Directory -Path "$directory/certs" -Force >$null
        New-Item -ItemType Directory -Path "$directory/certs/k8s" -Force >$null
        New-Item -ItemType Directory -Path "$directory/certs/docker" -Force >$null
        New-Item -ItemType Directory -Path "$directory/docker" -Force >$null
        New-Item -ItemType Directory -Path "$directory/system" -Force >$null
        New-Item -ItemType Directory -Path "$directory/network" -Force >$null
        New-Item -ItemType Directory -Path "$directory/network/hns" -Force >$null
        New-Item -ItemType Directory -Path "$directory/eventlogs" -Force >$null
        Write-Host "OK" -ForegroundColor "green"
    }
    catch {
        Write-Host "Unable to create temporary directory"
        Write-Host "Please ensure you have enough permissions to create directories"
        Write-Error "Failed to create temporary directory"
        Break
    }
}

Function get_sysinfo{
    try {
        Write-Host "Collecting System information"
        #systeminfo.exe > $directory\sysinfo
        systeminfo > $directory/system/systeminfo
        msinfo32 /nfo $directory/system/msinfo32-report.nfo /report $directory/system/msinfo32-report.txt
        (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootupTime > $directory/system/uptime
        # Get-PSDrive  > $directory\system\freediskspace
        # tree C:/var > $directory/system/tree-cvar
        # tree C:/etc > $directory/system/tree-cetc
        # tree C:/opt > $directory/system/tree-copt
        # tree C:/run > $directory/system/tree-crun
        Get-ChildItem env: > $directory/system/env

        Write-Host "OK" -ForegroundColor "green"
    }
    catch {
        Write-Error "Unable to collect system information" 
        Break
    }  
        
}

# collect functions
# ---------------------------------------------------------------------------------------

Function get_ps_info{
    try {
        Write-Host "Collecting PS output"
        ps > $directory/system/ps
        ps | sort -des cpu | select -f 50 | ft -a > $directory/system/ps-sortedcpu
        ps | sort -des pm | select -f 50 | ft -a > $directory/system/ps-sortedmem
        }
    catch {
        Write-Error "Unable to Collect PS Output"
        Break
    }
}

Function get_disk_info{
    try {
        Write-Host "Collecting Disk information"
        wmic OS get FreePhysicalMemory /Value > $directory/system/freememory
        wmic logicaldisk get size,freespace,caption > $directory/system/freediskspace
        wmic diskdrive get DeviceID,SystemName,Index,Size,InterfaceType,Partitions,Status,StatusInfo,CapabilityDescriptions,LastErrorCode > $directory/system/diskdriveget
    }
    catch {
        Write-Error "Unable to Collect Disk information"
        Break
    }
}

Function get_volumes_info{
    try {
        Write-Host "Collecting Volume info"
        Get-psdrive -PSProvider 'FileSystem' | Out-file $directory\volumes
        Write-Host "OK" -foregroundcolor "green"
    }
    catch {
        Write-Error "Unable to Collect Volume information"
        Break
    }
}

Function get_firewall_info{
    try {
        Write-Host "Collecting Windows Firewall info"
        $fw = Get-NetFirewallProfile
        foreach ($f in $fw){
            if ($f.Enabled -eq "True"){
                $file = $f.name
                Write-Host "Collecting Rules for" $f.name "profile"
                Get-NetFirewallProfile -Name $f.name | Get-NetFirewallRule | Out-file $directory\firewall\firewall-$file
                }
            }
        Get-NetFirewallRule | Where { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' } > $directory/network/firewallinbound
        Get-NetFirewallRule | Where { $_.Enabled -eq 'True' -and $_.Direction -eq 'Outbound' } > $directory/network/firewalloutbound
        Show-NetFirewallRule -PolicyStore ActiveStore > $directory/network/firewallactivepolicy
        Write-Host "OK" -foregroundcolor "green"
    }
    catch {
        Write-Error "Unable to Collect Windows Firewall information"
       
    }
}

Function get_software{
    try {
        Write-Host "Collecting installed applications list"
        gp HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |Select DisplayName, DisplayVersion, Publisher, InstallDate, HelpLink, UninstallString | out-file $directory\installed-64bit-apps.txt
        gp HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |Select DisplayName, DisplayVersion, Publisher, InstallDate, HelpLink, UninstallString | out-file $directory\installed-32bit-apps.txt
        Write-Host "OK" -foregroundcolor "green"
    }
    catch {
        Write-Error "Unable to collect installed applications list"
        Break
    }
}

Function get_system_services{
    try {
        Write-Host "Collecting Services list"
        get-service | fl | out-file $directory\services
        Write-Host "OK" -foregroundcolor "green"
    }
    catch {
        Write-Error "Unable to collect Services list"
        Break
    }
}

Function get_docker_info{
    try {
        Write-Host "Collecting Docker daemon information"
        docker info > $directory\docker\docker-info.txt 2>&1
        docker ps --all --no-trunc > $directory\docker\docker-ps.txt 2>&1
        docker images > $directory\docker\docker-images.txt 2>&1
        docker version > $directory\docker\docker-version.txt 2>&1
        Get-Content C:\ProgramData\docker\config\config.json > $directory/docker/dockerconfig.json 2>&1
        Write-Host "OK" -foregroundcolor "green"
    }
    catch{
        Write-Error "Unable to collect Docker daemon information"
        Break
    }
}

Function get_k8s_config {
    try {
        Write-Host "Collecting Kubernetes components config"
        Copy-Item -Path "C:\var\lib\cni\flannel\*" -Destination "$directory/config/cni/flannel" -Recurse
        Copy-Item -Path "C:\var\lib\cni\networks\*" -Destination "$directory/config/cni/networks" -Recurse
        Copy-Item -Path "C:\var\lib\cni\cache\results\*" -Destination "$directory/config/cni/cacheresults" -Recurse
        Copy-Item -Path "C:\var\lib\dockershim\sandbox\*" -Destination "$directory/config/dockershimsandbox" -Recurse
        Copy-Item -Path "C:\etc\rancher\wins\config" -Destination "$directory/config/wins/config" 
        Copy-Item -Path "C:\etc\kube-flannel\net-conf.json" -Destination "$directory/config/flannel/net-conf.json"
        Copy-Item -Path "C:\etc\cni\net.d\10-flannel.conflist" -Destination "$directory/config/cni/10-flannel.conflist" 
        Copy-Item -Path "C:\etc\nginx\conf\nginx.conf" -Destination "$directory/nginx/nginx.conf" 
        Write-Host "OK" -foregroundcolor "green"
    }
    catch {
        Write-Error "Unable to collect K8s config files"
        Break  
    }
}

Function get_certs{
    try {
        Write-Host "Collecting certificates for Docker and Kubernetes"
        Copy-Item -Path "C:\var\lib\kubelet\pki\kubelet.crt" -Destination "$directory/certs/kubelet.crt"
        Copy-Item -Path "C:\etc\kubernetes\ssl\*" -Destination "$directory/certs/k8s" -Recurse -Exclude *.key
        Copy-Item -Path "c:\ProgramData\docker\certs.d\" -Destination "$directory/certs/docker" -Recurse -ErrorAction SilentlyContinue
        Write-Host "OK" -foregroundcolor "green"
    }
    catch {
        Write-Error "Unable to collect certificates"
        Break
    }
}

Function get_windows_event_logs {
    try{
        Write-Host "Collecting Windows Event logs"

        Get-WinEvent -LogName "Application" -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/application.json"
        Get-WinEvent -LogName "System" -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/system.json"
        Get-WinEvent -LogName "Security" -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/security.json"

        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Storage-Storport%4Operational.evtx -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/storage-storport.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Hyper-V-VmSwitch-Operational.evtx -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/hyperv-vmswitch.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Host-Network-Service-Admin.evtx -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/hns-admin.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Security-Mitigations%4KernelMode.evtx -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/security-mitigations-kernelmode.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Hyper-V-Compute-Operational.evtx -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/hyperv-compute.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Hyper-V-Compute-Operational.evtx -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/hyperv-compute.json"
        Get-WinEvent -LogName "Microsoft-Windows-Windows Firewall With Advanced Security/ConnectionSecurity" -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/win-firewall-connection-security.json"
        Get-WinEvent -LogName "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall" -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/win-firewall.json"
        Get-WinEvent -LogName "Microsoft-Windows-Windows Firewall With Advanced Security/FirewallDiagnostics" -MaxEvents 5000 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/win-firewall-diagnostics.json"
        Write-Host "OK" -foregroundcolor "green"
    }
    catch {
        Write-Error "Unable to Collect Windows Event Logs"
        Break
    }
}

Function get_k8s_logs{
    try {
        Write-Host "Collecting Kubernetes Logs"
        $logPath =@(docker inspect -f '{{.LogPath}}' @(docker container ls --no-trunc --format '{{json .Names}}'))
        foreach ($file in $logPath){
            Copy-Item -Path $logPath -Destination "$directory/containerlogs/rke"
        }
        # $logfile =@(get-childitem -Recurse 'C:\var\lib\rancher\rke\log\' | Foreach-Object {$_.FullName})
        # $symlink = (Get-Item $logfile |  Select-Object -ExpandProperty Target)
        # $workinglink =  @(Get-Item $symlink  -ErrorAction SilentlyContinue| Where-Object {$_.Length -ne $null} | Foreach-Object {$_.FullName})
        # foreach ($file in $workinglink){
        #     Copy-Item -Path $workinglink -Destination "$directory/containerlogs/rke"
        # }
        Copy-Item -Path "C:\var\log\containers\*" -Destination "$directory/containerlogs" -Recurse
        Copy-Item -Path "C:\var\log\pods\*" -Destination "$directory/podlogs" -Recurse
        Copy-Item -Path "C:\etc\nginx\logs\*" -Destination "$directory/nginx/logs" -Recurse
        Write-Host "OK" -foregroundcolor "green"
    }
    catch {
        Write-Error "Unable to Collect Kubernetes Logs"
        Break
    }
}


Function get_network_info{
    try {
        Write-Host "Collecting network Information" 
        Get-HnsNetwork | Select Name, Type, Id, AddressPrefix > $directory\network\hns\network.txt
        Get-hnsnetwork | Convertto-json -Depth 20 >> $directory\network\hns\network.txt
        Get-hnsnetwork | % { Get-HnsNetwork -Id $_.ID -Detailed } | Convertto-json -Depth 20 >> $directory\network\hns\networkdetailed.txt

        Get-HnsEndpoint | Select IpAddress, MacAddress, IsRemoteEndpoint, State > $directory\network\hns\endpoint.txt
        Get-hnsendpoint | Convertto-json -Depth 20 >> $directory\network\hns\endpoint.txt

        Get-hnspolicylist | Convertto-json -Depth 20 > $directory\network\hns\policy.txt

        Get-NetAdapter "*" > $directory/network/networkadapter
        
        Get-NetRoute > $directory\network\networkroutes

        vfpctrl.exe /list-vmswitch-port > $directory\network\vfpports.txt
        ipconfig /allcompartments /all > $directory\network\ipconfigall.txt
        route PRINT -4 > $directory/network/ipv4routes.txt
        route PRINT -6 > $directory/network/ipv6routes.txt
        netsh interface ipv4 show subinterface > $directory/network/ipv4subinterfaces
        netsh interface ipv6 show subinterface > $directory/network/ipv6subinterfaces
        Get-Content C:\Windows\System32\drivers\etc\hosts > $directory/network/hosts.txt

        hnsdiag list all > $directory/network/hnsdiaglistall
        nslookup google.com > $directory/network/googlelookup 2>&1
        Resolve-DnsName google.com >> $directory/network/googlelookup
        netstat -r > $directory/network/netstatroute
        netstat -es > $directory/network/netstatstats
        netstat -qb > $directory/network/netstatall | Out-Null
        Write-Host "OK" -foregroundcolor "green"
    }
    catch {
        Write-Error "Unable to collect network information"
        #Break
    }
}

Function get_gp_info{
    try {
        Write-Host "Collecting group policy information" 
        if (Check-Command -cmdname 'Get-GPOReport')
        {
            Get-GPOReport -All -ReportType XML -Path "$directory\GPOReportsAll.xml"
            Write-Host "OK" -foregroundcolor "green"
        }
        else
        {
             Write-Host "Get-GPOReport is not a valid cmdlet"
        }

    }
    catch {
        Write-Error "Unable to collect group policy information"
        Break
    }
}

Function get_proxy_info{
    try {
        Write-Host "Collecting proxy information" 
        Get-ItemProperty -Path "Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"  > $directory/network/ie-proxy.txt
        Get-ChildItem env: | findstr PROXY > $directory/network/system-env-proxy.txt
        Get-ChildItem env: | findstr proxy >> $directory/network/system-env-proxy.txt
        Write-Host "OK" -foregroundcolor "green"
    }
    catch {
        Write-Error "Unable to collect proxy information"
        Break
    }
}

# main functions
# ---------------------------------------------------------------------------------------

Function compress{
    try {
        Write-Host "Archiving Rancher log collection script data"
        if (Check-Command -cmdname 'tar')
        {
            tar -czf "C:\$outfilename.tgz" -C C:\ rancher\log-collector 
            Write-Host "OK" -foregroundcolor "green"
        }
        else
        {
             Write-Host "tar is not a valid command"
        }
        #Compress-Archive -Path $directory\* -CompressionLevel Optimal -DestinationPath $basedir\$outfilename
        Write-Host "Done. Your log bundle is located in " "C:\"$outfilename
        Write-Host "Please supply the log bundle(s) to Rancher Support"
    }
    catch {
        Write-Error "Unable to archive data"
        Break
    }
}

Function cleanup{
    Write-Host "Cleaning up directory"
    Remove-Item -Recurse -Force $directory -ErrorAction Ignore
    Write-Host "OK" -foregroundcolor green
}

Function init{
    is_elevated
    create_working_dir
    get_sysinfo
}
    
Function collect{
    init
    get_ps_info
    get_disk_info
    get_volumes_info
    get_firewall_info
    get_software
    get_system_services
    get_docker_info
    get_k8s_config
    get_windows_event_logs
    get_k8s_logs
    get_network_info
    get_gp_info
    get_proxy_info
}


# Main function
Function main {   
    Write-Host "Running Rancher Log Collection" -foregroundcolor "yellow"
    collect
    compress 
    cleanup
}

# Entry point
main
