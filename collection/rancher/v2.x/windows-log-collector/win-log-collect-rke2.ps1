<#
.SYNOPSIS
    Collects Rancher logs from RKE2 Windows Worker Nodes

.DESCRIPTION
    Run the script to gather troubleshooting information on the OS, containerd, network, system, and grab all relevant
    RKE2 (containerd-based) logs, including wins and csiproxy service information.

.NOTES
    This script needs to be run with Elevated permissions to allow for the complete collection of information.
    Once the script has completed, please supply the .tar.gz file to Rancher Support.

.EXAMPLE
    `powershell win-log-collect-rke2.ps1`
#>
Param(
    [Parameter(HelpMessage="Override the host prefix path (default C:\)")]
    [Alias("p")]
    [String] $hostPrefixPath = "C:\",

    [Parameter(HelpMessage="Override the temporary directory (default C:\rancher)")]
    [Alias("d")]
    [String] $baseDir = "C:\rancher",

    [Parameter(HelpMessage="Override the output location for compressed log bundle (default C:\)")]
    [Alias("o")]
    [String] $outputDir = "C:\",

    [Parameter(HelpMessage="Override the number of days history to collect from container/service logs (default 30d)")]
    [ValidatePattern("\d{1,3}[d]")]
    [Alias("s")]
    [String] $sinceFlag = "30d",

    [Parameter(HelpMessage="Override the RKE2 data directory (default C:\var\lib\rancher\rke2)")]
    [String] $rke2DataDir,

    [Parameter(HelpMessage="Override the RKE2 config directory (default C:\etc\rancher\rke2)")]
    [String] $rke2ConfigDir
)

# set utf8 as PS defaults to utf16
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# set default directories and replace / with \
if ($baseDir.Contains("/")) {
    $baseDir = $baseDir -Replace "/", "\"
}

if ($outputDir.Contains("/")) {
    $outputDir = $outputDir -Replace "/", "\"
}

# RKE2 agent processes/services running natively on the Windows node (no docker/dockershim)
$rke2Services = @('rke2', 'rancher-wins', 'csiproxy')

# Kubernetes system namespaces to gather containerd/crictl logs for
$systemNamespaces = @('kube-system', 'cattle-system', 'cattle-fleet-system', 'cattle-fleet-local-system', 'ingress-nginx', 'cattle-monitoring-system')

# default options
$currentTime = get-date -Format yyyy-MM-dd_HH_mm_ss
$outFileName = "rancher_rke2_" + "$(hostname)" + "_" + $currentTime
$logCollectorDir = $baseDir + "\log-collector"
# nest output under a hostname/timestamp directory so multiple bundles can be unpacked into the same folder without colliding
$directory = $logCollectorDir + "\" + $outFileName
$origDir = $PSScriptRoot
$finalFile = $outputDir + "\" + $outFileName + ".tar.gz"

# Windows host prefix path
Write-Host "Validating Windows host prefix path"
if ($hostPrefixPath.Contains("/")) {
    $hostPrefixPath = $hostPrefixPath -Replace "/", "\"
}
if (-not $hostPrefixPath.EndsWith("\")) {
    $hostPrefixPath = $hostPrefixPath + "\"
}
if (-not (Test-Path -Path $hostPrefixPath)) {
    Write-Warning "Host prefix path '$hostPrefixPath' does not exist, falling back to default 'C:\'"
    $hostPrefixPath = "C:\"
}
Write-Host "Validating Windows host prefix path - OK" -ForegroundColor "green"


# RKE2 data/config directories
if (!$rke2DataDir) {
    $rke2DataDir = $hostPrefixPath + "var\lib\rancher\rke2"
} elseif ($rke2DataDir.Contains("/")) {
    $rke2DataDir = $rke2DataDir -Replace "/", "\"
}

if (!$rke2ConfigDir) {
    $rke2ConfigDir = $hostPrefixPath + "etc\rancher\rke2"
} elseif ($rke2ConfigDir.Contains("/")) {
    $rke2ConfigDir = $rke2ConfigDir -Replace "/", "\"
}

# Set the length of collection for container/service logs
$sinceDays = [int]($sinceFlag.Replace("d", ""))
$logSinceDate = (Get-Date).AddDays(-$sinceDays)
$crictlSinceDuration = "$($sinceDays * 24)h"

# init functions
# ---------------------------------------------------------------------------------------

function is_elevated {
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Information "This script requires elevated privileges."
        Write-Error "Please re-launch as Administrator." -Category PermissionDenied
        throw
    }
}

function check_command ($cmdname) {
    return [bool](Get-Command -Name $cmdname -ErrorAction SilentlyContinue)
}

function test_and_copy ($source, $destination, $recurse) {
    if (-not (Test-Path -Path $source)) {
        Write-Warning "Path not found, skipping: $source"
        return
    }
    try {
        if ($recurse) {
            Copy-Item -Path $source -Destination $destination -Recurse -Force -ErrorAction Stop
        } else {
            Copy-Item -Path $source -Destination $destination -Force -ErrorAction Stop
        }
    }
    catch {
        Write-Warning "Unable to copy '$source' to '$destination': $_"
    }
}

function create_working_dir {
    try {
        Write-Host "Creating temporary directory"
        $directoriesToCreate = @(
            "$directory",
            "$directory/k8s/containerlogs",
            "$directory/k8s/containerinspect",
            "$directory/k8s/components",
            "$directory/containerd",
            "$directory/config",
            "$directory/config/rke2",
            "$directory/config/cni",
            "$directory/config/wins",
            "$directory/certs/rke2",
            "$directory/system",
            "$directory/network",
            "$directory/network/hns",
            "$directory/eventlogs",
            "$directory/firewall",
            "$directory/services"
        )

        foreach ($dirPath in $directoriesToCreate) {
            try {
                New-Item -ItemType Directory -Path $dirPath -Force -ErrorAction Stop | Out-Null
            }
            catch {
                throw "Failed to create directory '$dirPath': $($_.Exception.Message)"
            }
        }
        # Create the output directory if it doesn't exist
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
        Write-Host "Collecting System information - OK" -ForegroundColor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect system information"
    }
}


# collect functions
# ---------------------------------------------------------------------------------------

function get_ps_info{
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

function get_disk_info{
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

function get_firewall_info{
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

function get_system_services{
    try {
        Write-Host "Collecting Services list"
        get-service | Format-List | out-file $directory\system\services
        Write-Host "Collecting Services list - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect Services list"
    }
}

function get_rke2_services_status {
    try {
        Write-Host "Collecting RKE2 core service status (rke2, rancher-wins, csiproxy)"
        foreach ($svcName in $rke2Services) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                $svc | Format-List * | Out-File "$directory/services/$svcName-status.txt"
            } else {
                Write-Warning "Service '$svcName' was not found on this node, skipping"
            }
        }
        Write-Host "Collecting RKE2 core service status - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect RKE2 core service status"
    }
}

function get_containerd_info{
    try {
        Write-Host "Collecting containerd runtime information"

        if (check_command -cmdname "ctr.exe") {
            ctr.exe version > $directory\containerd\ctr-version.txt 2>&1
            ctr.exe --namespace k8s.io containers list > $directory\containerd\ctr-containers.txt 2>&1
            ctr.exe --namespace k8s.io images list > $directory\containerd\ctr-images.txt 2>&1
        } else {
            Write-Warning "ctr.exe not found in PATH, skipping ctr collection"
        }

        if (check_command -cmdname "crictl.exe") {
            crictl.exe info > $directory\containerd\crictl-info.txt 2>&1
            crictl.exe ps -a > $directory\containerd\crictl-ps.txt 2>&1
            crictl.exe images > $directory\containerd\crictl-images.txt 2>&1
            crictl.exe pods > $directory\containerd\crictl-pods.txt 2>&1
        } else {
            Write-Warning "crictl.exe not found in PATH, skipping crictl collection"
        }

        test_and_copy (Join-Path $rke2DataDir "agent\etc\containerd\config.toml") "$directory/containerd/config.toml" $false
        test_and_copy (Join-Path $rke2DataDir "agent\containerd\containerd.log") "$directory/containerd/containerd.log" $false
        Write-Host "Collecting containerd runtime information - OK" -foregroundcolor "green"
    }
    catch{
        Write-Host $_
        Write-Warning "Unable to collect containerd runtime information"
    }
}

function get_k8s_config {
    try {
        Write-Host "Collecting Kubernetes/RKE2 components config"
        test_and_copy "$($rke2ConfigDir)\config.yaml" "$directory/config/rke2/config.yaml" $false
        test_and_copy "$($rke2ConfigDir)\config.yml" "$directory/config/rke2/config.yml" $false
        test_and_copy "$($rke2ConfigDir)\config.yaml.d\*.yaml" "$directory/config/rke2" $true
        test_and_copy "$($rke2ConfigDir)\config.yaml.d\*.yml" "$directory/config/rke2" $true
        test_and_copy (Join-Path $rke2DataDir "agent\etc\kubelet.conf.d\00-rke2-defaults.conf") "$directory/config/rke2/00-rke2-defaults.conf" $false
        test_and_copy (Join-Path $rke2DataDir "agent\etc\cni\*") "$directory/config/cni" $true
        test_and_copy "$($hostPrefixPath)etc\rancher\wins\config" "$directory/config/wins/config" $false
        Write-Host "Collecting Kubernetes/RKE2 components config - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect K8s/RKE2 config files"
    }
}

function get_certs{
    try {
        Write-Host "Collecting certificates for RKE2"
        test_and_copy (Join-Path $rke2DataDir "agent\client-kubelet.crt") "$directory/certs/rke2/client-kubelet.crt" $false
        test_and_copy (Join-Path $rke2DataDir "agent\serving-kubelet.crt") "$directory/certs/rke2/serving-kubelet.crt" $false
        test_and_copy (Join-Path $rke2DataDir "agent\client-ca.crt") "$directory/certs/rke2/client-ca.crt" $false
        test_and_copy (Join-Path $rke2DataDir "agent\server-ca.crt") "$directory/certs/rke2/server-ca.crt" $false
        Write-Host "Collecting certificates for RKE2 - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect certificates"
    }
}

function get_windows_event_logs {
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

function get_rke2_agent_logs {
    try {
        Write-Host "Collecting RKE2 agent component logs (kubelet, kube-proxy, rke2)"
        # rke2 is the only agent process running natively on the Windows worker node.
        # kubelet and kube-proxy run as containers under rke2, but rke2 also writes
        # their logs directly to the agent logs directory as kubelet.log/kube-proxy.log.
        $agentLogDir = Join-Path $rke2DataDir "agent\logs"
        test_and_copy (Join-Path $agentLogDir "kubelet.log") "$directory/k8s/components/kubelet.log" $false
        test_and_copy (Join-Path $agentLogDir "kube-proxy.log") "$directory/k8s/components/kube-proxy.log" $false

        # RKE2 service event logs via Get-EventLog (reliable source for rke2 on Windows)
        Get-EventLog -LogName Application -Source 'rke2' -After $logSinceDate -ErrorAction SilentlyContinue |
            Select-Object -Property ReplacementStrings, TimeWritten |
            Format-Table -Wrap -AutoSize | Out-File "$directory/eventlogs/rke2-service.txt"

        # Capture command-line args for the natively running RKE2 process
        Get-WmiObject Win32_Process -Filter "name = 'rke2.exe'" -ErrorAction SilentlyContinue |
            Select-Object CommandLine |
            Out-File "$directory/k8s/components/rke2-cmdline.txt"

        Write-Host "Collecting RKE2 agent component logs - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to Collect RKE2 agent component logs"
    }
}

function get_k8s_container_logs{
    try {
        Write-Host "Collecting Kubernetes container logs via crictl"

        if (-not (check_command -cmdname "crictl.exe")) {
            Write-Warning "crictl.exe not found in PATH, skipping container log collection"
            return
        }

        foreach ($ns in $systemNamespaces) {
            $containersJson = crictl.exe ps -a --label "io.kubernetes.pod.namespace=$ns" -o json 2>$null
            if (-not $containersJson) {
                continue
            }

            try {
                $containers = ($containersJson | ConvertFrom-Json).containers
            }
            catch {
                Write-Warning "Unable to parse crictl output for namespace '$ns'"
                continue
            }

            if (-not $containers -or $containers.Count -eq 0) {
                Write-Host "No containers found in namespace '$ns', skipping" -ForegroundColor "green"
                continue
            }

            foreach ($c in $containers) {
                $name = $c.metadata.name
                $id = $c.id
                $safeName = ($name -replace '[^a-zA-Z0-9._-]', '_')
                $shortId = if ($id.Length -ge 12) { $id.Substring(0, 12) } else { $id }
                $outputBase = "$safeName-$shortId"
                crictl.exe inspect $id > "$directory/k8s/containerinspect/$outputBase.json" 2>&1
                crictl.exe logs --since $crictlSinceDuration $id > "$directory/k8s/containerlogs/$outputBase.log" 2>&1
            }
        }
        Write-Host "Collecting Kubernetes container logs via crictl - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to Collect Kubernetes container logs"
    }
}

function get_wins_info{
    try {
        Write-Host "Collecting rancher-wins service information"
        $winsSvc = Get-WmiObject win32_service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*rancher-wins*' }
        if (-not $winsSvc) {
            Write-Warning "rancher-wins service not found on this node, skipping"
            return
        }

        # rancher-wins event logs via Get-EventLog
        Get-EventLog -LogName Application -Source 'rancher-wins' -After $logSinceDate -ErrorAction SilentlyContinue |
            Out-File "$directory/eventlogs/rancher-wins-service.txt"

        Write-Host "Collecting rancher-wins service information - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect rancher-wins service information"
    }
}

function get_csi_proxy_info{
    try {
        Write-Host "Collecting csiproxy service information"
        $csiSvc = Get-Service -Name "csiproxy" -ErrorAction SilentlyContinue
        if (-not $csiSvc) {
            Write-Warning "csiproxy service not found on this node, skipping"
            return
        }
        test_and_copy "$($hostPrefixPath)etc\rancher\wins\csi-proxy.log" "$directory/eventlogs/csi-proxy.log" $false

        Write-Host "Collecting csiproxy service information - OK" -foregroundcolor "green"
    }
    catch {
        Write-Host $_
        Write-Warning "Unable to collect csiproxy service information"
    }
}

function get_network_info{
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

function get_gp_info{
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

function get_proxy_info{
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

function compress{
    try {
        Write-Host "Archiving Rancher RKE2 log collection script data"
        if (-not (check_command -cmdname 'tar')) {
            throw "tar is not a valid command"
        }

        Set-Location $logCollectorDir
        tar -czf "$finalFile" "$outFileName"
        if ($LASTEXITCODE -ne 0) {
            throw "tar failed with exit code $LASTEXITCODE"
        }
        if (-not (Test-Path -Path $finalFile)) {
            throw "Archive file was not created: $finalFile"
        }

        Write-Host "Archiving Rancher RKE2 log collection script data - OK" -foregroundcolor "Green"
        Write-Host "Your log bundle is located in " $finalFile -ForegroundColor "cyan"
        Write-Host "Please supply the log bundle(s) to Rancher Support"  -ForegroundColor "cyan"
    }
    catch {
        Write-Host $_
        Write-Error "Unable to archive data"
        throw
    }
    finally {
        Set-Location $origDir -ErrorAction SilentlyContinue
    }
}

function cleanup{
    Write-Host "Cleaning up temporary directory"
    Remove-Item -Recurse -Force $logCollectorDir -ErrorAction Ignore
    Write-Host "Cleaning up temporary directory - OK" -foregroundcolor "Green"
}

function setup_env {
    Write-Host "Configuring environment for RKE2 tooling"
    $env:PATH += ";$($rke2DataDir)\bin;$($hostPrefixPath)usr\local\bin"
    $Env:CRI_CONFIG_FILE = Join-Path $rke2DataDir "agent\etc\crictl.yaml"
    Write-Host "Configuring environment for RKE2 tooling - OK" -ForegroundColor "green"
}

function init{
    is_elevated
    create_working_dir
    get_sysinfo
    setup_env
}

function collect{
    init
    get_ps_info
    get_disk_info
    get_firewall_info
    get_system_services
    get_rke2_services_status
    get_containerd_info
    get_k8s_config
    get_certs
    get_windows_event_logs
    get_rke2_agent_logs
    get_k8s_container_logs
    get_wins_info
    get_csi_proxy_info
    get_network_info
    get_gp_info
    get_proxy_info
}


# Main function
function main {
    Write-Host "Running Rancher RKE2 Log Collection" -foregroundcolor "Cyan"
    collect
    compress
    cleanup
}

# Entry point
main
