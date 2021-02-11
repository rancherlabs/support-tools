<#
.SYNOPSIS
    Collects Rancher logs from Windows Worker Nodes

.DESCRIPTION
    Run the script to gather troubleshooting information on the OS, Docker, network, system, and grab all relevant logs.

.NOTES
    This script needs to be run with Elevated permissions to allow for the complete collection of information.
    Once the script has completed, please supply the .tar.gz file to Rancher Support.

.EXAMPLE
    `powershell win-log-collect.ps1`
#>
Param(
    [Parameter(HelpMessage="Override the win_prefix_path (default C:\)")]
    [Alias("p")]
    [String] $hostPrefixPath,

    [Parameter(HelpMessage="Override the temporary directory (default C:\rancher)")]
    [Alias("d")]
    [String] $baseDir,

    [Parameter(HelpMessage="Override the output location for compressed log bundle (default C:\)")]
    [Alias("o")]
    [String] $outputDir,

    [Parameter(HelpMessage="Override the number of days history to collect from docker logs (default 30d")]
    [ValidatePattern("\d{1,3}[d]")]
    [Alias("s")]
    [String] $sinceFlag
)

# set utf8 as PS defaults to utf16
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# TODO add better validation for cli params
# TODO set timeout in seconds for select commands
#$timeout = 120
# TODO Minimum space required to run the script in MB
#$minSpace = 1024
# TODO allow for collection of evtx files instead of converting to json via flag

# set default directories and replace / with \
if (!$baseDir) {
    $baseDir = "C:\rancher"
} elseif ($baseDir.Contains("/")) {
    $baseDir = $baseDir -Replace "/", "\"
}

if (!$outputDir) {
    $outputDir = "C:\"
} elseif ($outputDir.Contains("/")) {
    $outputDir = $outputDir -Replace "/", "\"
}
# Included RKE container logs
$rkeContainers = @('kubelet', 'service-sidekick', 'kube-proxy', 'nginx-proxy')

# default options
$directory =  $baseDir + "\log-collector"
$currentTime = get-date -Format yyyy-MM-dd
$outFileName = "rancher_" + "$(hostname)" + "_" + $currentTime
$origDir = $PSScriptRoot
$finalFile = $outputDir + "\" + $outFileName + ".tar.gz"

# Windows Prefix Path
if (!$hostPrefixPath) {
    $hostPrefixPath = "C:\"
} elseif ($hostPrefixPath.Contains("/")) {
    $hostPrefixPath = $hostPrefixPath -Replace "/", "\"
}

# Set the length of collection for docker logs
if (!$sinceFlag) {
    $dockerDate = Get-Date (Get-Date).AddDays(-30) -format "yyyy-MM-ddThh:mm:ss"
} elseif ($sinceFlag){
    $dockerDate = Get-Date (Get-Date).AddDays(-$sinceFlag.Replace("d","")) -format "yyyy-MM-ddThh:mm:ss"
}

Function get_prefix_path {
    Write-Host "Getting Windows prefix path"
    $rkeDefaultPrefix = "c:/"
    $dockerStatus = (docker info) | Out-Null
    try {
        $hostPrefixPath = (docker exec kubelet pwsh -c 'Get-ChildItem env:' 2>&1| findstr RKE_NODE_PREFIX_PATH).Trim("RKE_NODE_PREFIX_PATH").Trim(" ")

        if ($dockerstatus.ExitCode -ne 0 -and !$hostPrefixPath) {
            $hostPrefixPath = "c:\"
        } elseif ($hostPrefixPath)
        {
            if ($rkeDefaultPrefix -ine $hostPrefixPath)
            {
                $hostPrefixPath = $hostPrefixPath -Replace "/", "\"
                if ($hostPrefixPath.Chars($hostPrefixPath.Length - 1) -ne '\')
                {
                    $hostPrefixPath = $( $hostPrefixPath + '\' )
                }
            }
        }
        return Write-Host "Getting Windows prefix path - OK"  -ForegroundColor "green"
    }
    catch {
        Write-Warning "Unable to find the host prefix path, it has been set to the default: 'c:\'"
    }
}

# init functions
# ---------------------------------------------------------------------------------------

Function is_elevated {
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Information "This script requires elevated privileges."
        Write-Error "Please re-launch as Administrator." -Category PermissionDenied -foreground "red" -background "black"
        throw
    }
}

function check_command ($cmdname) {
    return [bool](Get-Command -Name $cmdname -ErrorAction SilentlyContinue)
}

function create_working_dir {
    try {
        Write-Host "Creating temporary directory"
        New-Item -ItemType Directory -Path "$directory" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/k8s/containerlogs" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/k8s/containerinspect" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/podlogs" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/nginx" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/nginx/logs" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/config" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/config/cni" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/config/cni/networks" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/config/cni/flannel" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/config/wins" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/config/flannel" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/certs" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/certs/k8s" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/certs/docker" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/docker" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/system" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/network" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/network/hns" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/eventlogs" -Force | Out-Null
        New-Item -ItemType Directory -Path "$directory/firewall" -Force | Out-Null
        New-Item -ItemType Directory -Path "$outputDir" -ErrorAction SilentlyContinue | Out-Null
        Write-Host "Creating temporary directory - OK" -ForegroundColor "green"
    }
    catch {
        Write-Host $_
        Write-Host "Unable to create temporary directory"
        Write-Host "Please ensure you have correct permissions to create directories"
        Write-Error "Failed to create temporary directory" -Category WriteError
        throw
    }
}

function get_sysinfo {
    try {
        Write-Host "Collecting System information"
        $uptime = ((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootupTime)
        systeminfo > $directory/system/systeminfo
        msinfo32 /nfo $directory/system/msinfo32-report.nfo /report $directory/system/msinfo32-report.txt
        $uptime > $directory/system/uptime
        Get-ChildItem env: > $directory/system/env
        Write-Host "Collecting System information - OK" -ForegroundColor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect system information"
    }

}

# collect functions
# ---------------------------------------------------------------------------------------

Function get_ps_info{
    try {
        Write-Host "Collecting PS output"
        Get-Process > $directory/system/ps
        Get-Process | Sort-Object -des cpu | Select-Object -f 50 | Format-Table -a > $directory\system\ps-sortedcpu
        Get-Process | Sort-Object -des pm | Select-Object -f 50 | Format-Table -a > $directory\system\ps-sortedmem
        Write-Host "Collecting PS output - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to Collect PS Output"
    }
}

Function get_disk_info{
    try {
        Write-Host "Collecting Disk and Volume information"
        wmic OS get FreePhysicalMemory /Value > $directory/system/freememory
        Get-PSDrive > $directory/system/freediskspace
        wmic logicaldisk get size,freespace,caption >> $directory/system/freediskspace
        Get-Disk > $directory/system/diskinfo
        Get-DiskStorageNodeView >> $directory/system/diskinfo
        wmic diskdrive get DeviceID,SystemName,Index,Size,InterfaceType,Partitions,Status,StatusInfo,CapabilityDescriptions,LastErrorCode >> $directory/system/diskinfo
        Get-psdrive -PSProvider 'FileSystem' | Out-file $directory/system/volumes
        Write-Host "Collecting Disk and Volume information - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to Collect Disk and Volume information"
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
        Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' } > $directory/network/firewallinbound
        Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Outbound' } > $directory/network/firewalloutbound
        Show-NetFirewallRule -PolicyStore ActiveStore > $directory/network/firewallactivepolicy
        Write-Host "Collecting Windows Firewall info - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to Collect Windows Firewall information"
    }
}

Function get_software{
    try {
        Write-Host "Collecting installed applications list"
        Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, HelpLink, UninstallString | out-file $directory\installed-64bit-apps.txt
        Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, HelpLink, UninstallString | out-file $directory\installed-32bit-apps.txt
        Write-Host "Collecting installed applications list - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect installed applications list"
    }
}

Function get_system_services{
    try {
        Write-Host "Collecting Services list"
        get-service | Format-List | out-file $directory\services
        Write-Host "Collecting Services list - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect Services list"
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
        Write-Host "Collecting Docker daemon information - OK" -foregroundcolor "green"
    }
    catch{
        Write-Host $_
        Write-Warning "Unable to collect Docker daemon information"
    }
}

Function get_k8s_config {
    try {
        Write-Host "Collecting Kubernetes components config"
        Copy-Item -Path "$($hostPrefixPath)var\lib\cni\flannel\*" -Destination "$directory/config/cni/flannel" -Recurse
        Copy-Item -Path "$($hostPrefixPath)var\lib\cni\networks\*" -Destination "$directory/config/cni/networks" -Recurse
        Copy-Item -Path "$($hostPrefixPath)var\lib\cni\cache\results\*" -Destination "$directory/config/cni/cacheresults" -Recurse
        Copy-Item -Path "$($hostPrefixPath)var\lib\dockershim\sandbox\*" -Destination "$directory/config/dockershimsandbox" -Recurse
        Copy-Item -Path "$($hostPrefixPath)etc\rancher\wins\config" -Destination "$directory/config/wins/config"
        Copy-Item -Path "$($hostPrefixPath)etc\kube-flannel\net-conf.json" -Destination "$directory/config/flannel/net-conf.json"
        Copy-Item -Path "$($hostPrefixPath)etc\cni\net.d\10-flannel.conflist" -Destination "$directory/config/cni/10-flannel.conflist"
        Copy-Item -Path "$($hostPrefixPath)etc\nginx\conf\nginx.conf" -Destination "$directory/nginx/nginx.conf"
        Write-Host "Collecting Kubernetes components config - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect K8s config files"
    }
}

Function get_certs{
    try {
        Write-Host "Collecting certificates for Docker and Kubernetes"
        Copy-Item -Path "$($hostPrefixPath)var\lib\kubelet\pki\kubelet.crt" -Destination "$directory/certs/kubelet.crt"
        Copy-Item -Path "$($hostPrefixPath)etc\kubernetes\ssl\*" -Destination "$directory/certs/k8s" -Recurse -Exclude *.key
        Copy-Item -Path "$($hostPrefixPath)ProgramData\docker\certs.d\" -Destination "$directory/certs/docker" -Recurse -ErrorAction SilentlyContinue
        Write-Host "Collecting certificates for Docker and Kubernetes - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect certificates"
    }
}

Function get_windows_event_logs {
    try{
        Write-Host "Collecting Windows Event logs"

        Get-WinEvent -LogName "Application" -MaxEvents 2500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/application.json"
        Get-WinEvent -LogName "System" -MaxEvents 2500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/system.json"
        Get-WinEvent -LogName "Security" -MaxEvents 2500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/security.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Storage-Storport%4Operational.evtx -MaxEvents 500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/storage-storport.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Hyper-V-VmSwitch-Operational.evtx -MaxEvents 500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/hyperv-vmswitch.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Host-Network-Service-Admin.evtx -MaxEvents 500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/hns-admin.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Security-Mitigations%4KernelMode.evtx -MaxEvents 500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/security-mitigations-kernelmode.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Hyper-V-Compute-Operational.evtx -MaxEvents 500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/hyperv-compute.json"
        Get-WinEvent -Path C:\Windows\system32\winevt\logs\Microsoft-Windows-Hyper-V-Compute-Operational.evtx -MaxEvents 500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/hyperv-compute.json"
        Get-WinEvent -LogName "Microsoft-Windows-Windows Firewall With Advanced Security/ConnectionSecurity" -MaxEvents 500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/win-firewall-connection-security.json"
        Get-WinEvent -LogName "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall" -MaxEvents 500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/win-firewall.json"
        Get-WinEvent -LogName "Microsoft-Windows-Windows Firewall With Advanced Security/FirewallDiagnostics" -MaxEvents 500 -ErrorAction SilentlyContinue | ConvertTo-Json > "$directory/eventlogs/win-firewall-diagnostics.json"
        Write-Host "Collecting Windows Event logs - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to Collect Windows Event Logs"
    }
}

Function get_k8s_logs{
    try {
        $systemNamespace = @('kube-system', 'kube-public', 'cattle-system', 'cattle-alerting', 'cattle-logging', 'cattle-pipeline', 'ingress-nginx', 'cattle-prometheus', 'istio-system', 'longhorn-system', 'cattle-global-data', 'fleet-system', 'fleet-default', 'rancher-operator-system')
        Write-Host "Collecting Kubernetes Logs"
        foreach ($rkeContainer in $rkeContainers){
            docker inspect $rkeContainer > $directory/k8s/containerinspect/$rkeContainer
            docker logs --since $dockerDate -t $rkeContainer 2>&1 > $directory/k8s/containerlogs/$rkeContainer
        }

        foreach ($sysns in $systemNamespace)
        {
            $sysContainers = (docker ps -a --filter name=$sysns --format "{{.Names}}")
            foreach ($sysContainer in $sysContainers) {
                docker inspect $sysContainer > $directory/k8s/containerinspect/$sysContainer
                docker logs --since $dockerDate -t $sysContainer 2>&1 > $directory/k8s/containerlogs/$sysContainer
            }
        }
        Copy-Item -Path "$($hostPrefixPath)etc\nginx\logs\*" -Destination "$directory/nginx/logs" -Recurse
        Write-Host "Collecting Kubernetes Logs - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to Collect Kubernetes Logs"
    }
}


Function get_network_info{
    try {
        Write-Host "Collecting network Information"
        Get-HnsNetwork | Select-Object Name, Type, Id, AddressPrefix > $directory\network\hns\network.txt
        Get-hnsnetwork | Convertto-json -Depth 20 >> $directory\network\hns\network.txt
        Get-hnsnetwork | ForEach-Object { Get-HnsNetwork -Id $_.ID -Detailed } | Convertto-json -Depth 20 >> $directory\network\hns\networkdetailed.txt
        Get-HnsEndpoint | Select-Object IpAddress, VirtualNetworkName, IsRemoteEndpoint, State, EncapOverhead, SharedContainers > $directory\network\hns\endpoint.txt
        Get-hnsendpoint | Convertto-json -Depth 20 >> $directory\network\hns\endpoint.txt
        Get-hnspolicylist | Convertto-json -Depth 20 > $directory\network\hns\policy.txt
        Get-NetAdapter > $directory/network/networkadapter
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
        Write-Host "Collecting network Information - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect network information"
    }
}

Function get_gp_info{
    try {
        Write-Host "Collecting group policy information"
        if (check_command -cmdname 'Get-GPOReport')
        {
            Get-GPOReport -All -ReportType XML -Path "$directory\GPOReportsAll.xml"
            Write-Host "Collecting group policy information - OK" -foregroundcolor "green"
        }
        else
        {
            Write-Host "Get-GPOReport is not a valid cmdlet"
        }
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect group policy information"
    }
}

Function get_proxy_info{
    try {
        Write-Host "Collecting proxy information"
        Get-ItemProperty -Path "Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"  > $directory/network/ie-proxy.txt
        Get-ChildItem env: | findstr PROXY > $directory/network/system-env-proxy.txt
        Get-ChildItem env: | findstr proxy >> $directory/network/system-env-proxy.txt
        Write-Host "Collecting proxy information - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect proxy information"
    }
}

# main functions
# ---------------------------------------------------------------------------------------

Function compress{
    try {
        Write-Host "Archiving Rancher log collection script data"
        if (check_command -cmdname 'tar')
        {
            Set-Location $directory
            tar -czf $finalFile .
        }
        else
        {
            Write-Host "tar is not a valid command"
        }
        Set-Location $origDir
        Write-Host "Archiving Rancher log collection script data - OK" -foregroundcolor "Green"
        Write-Host "Your log bundle is located in " $finalFile -ForegroundColor "cyan"
        Write-Host "Please supply the log bundle(s) to Rancher Support"  -ForegroundColor "cyan"
    }
    catch {
        Write-Host $_
        Write-Error "Unable to archive data"
        Set-Location $origDir
        throw
    }
}

Function cleanup{
    Write-Host "Cleaning up temporary directory"
    Remove-Item -Recurse -Force $directory -ErrorAction Ignore
    Write-Host $_
    Write-Host "Cleaning up temporary directory - OK" -foregroundcolor "Green"
}

Function init{
    is_elevated
    create_working_dir
    get_sysinfo
    get_prefix_path
}

Function collect{
    init
    get_ps_info
    get_disk_info
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
    Write-Host "Running Rancher Log Collection" -foregroundcolor "Cyan"
    collect
    compress
    cleanup
}

# Entry point
main
