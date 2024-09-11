<#
    .SYNOPSIS
    Updates the rancher_connection_info.json file on Windows nodes and optionally downloads the latest version of rancher-wins from the specified Rancher server

    .PARAMETER RancherServerURL
    The HTTPs URL of the Rancher server which manages the cluster this node is joined to

    .PARAMETER Token
    The Rancher API token tracked in the stv-aggregation secret

    .PARAMETER ForceRegeneration
    When set to true, this script will overwrite the rancher2_connection_info.json file, even if the cetificate-authority-data field is present

    .PARAMETER DownloadWins
    When set to true, this script will reach out to the RancherServerURL API and download the version of rancher-wins embedded in that sever
#>

param (
    [Parameter()]
    [String]
    $RancherServerURL,

    [Parameter()]
    [String]
    $Token,

    [Parameter()]
    [Switch]
    $ForceRegeneration,

    [Parameter()]
    [Switch]
    $DownloadWins
)

if ($DownloadWins -eq $true) {
    # Download the latest verson of wins from the rancher server
    $responseCode = $(curl.exe --connect-timeout 60 --max-time 300 --write-out "%{http_code}\n" --ssl-no-revoke -sfL "$RancherServerURL/assets/wins.exe" -o "/usr/local/bin/wins.exe")
    switch ( $responseCode ) {
        { "ok200", 200 } {
            Write-LogInfo "Successfully downloaded the wins binary."
            break
        }
        default {
            Write-LogError "$responseCode received while downloading the wins binary. Double check that the correct RancherServerURL has been provided"
            exit 1
        }
    }
    Copy-Item -Path "/usr/local/bin/wins.exe" -Destination "c:\Windows\wins.exe" -Force
}

# Check the current connection file to determine if CA data is already present.
$info = (Get-Content C:\var\lib\rancher\agent\rancher2_connection_info.json -ErrorAction Ignore)
if (($null -ne $info) -and (($info | ConvertFrom-Json).kubeConfig).Contains("certificate-authority-data")) {
    if (-Not $ForceRegeneration) {
        Write-Host "certificate-authority-data is already present in rancher2_connection_info.json"
        exit 0
    }
}

$CATTLE_ID=(Get-Content /etc/rancher/wins/cattle-id -ErrorAction Ignore)
if (($null -eq $CATTLE_ID) -or ($CATTLE_ID -eq "")) {
    Write-Host "Could not obtain required CATTLE_ID value from node"
    exit 1
}

Write-Host "Updating rancher2_connection_info.json file"

$responseCode = $(curl.exe --connect-timeout 60 --max-time 60 --write-out "%{http_code}\n " --ssl-no-revoke -sfL "$RancherServerURL/v3/connect/agent" -o /var/lib/rancher/agent/rancher2_connection_info.json -H "Authorization: Bearer $Token" -H "X-Cattle-Id: $CATTLE_ID" -H "Content-Type: application/json")

switch ( $responseCode ) {
    { $_ -in "ok200", 200 } {
        Write-Host "Successfully downloaded Rancher connection information."
        exit 0
    }
    default {
        Write-Host "$responseCode received while downloading Rancher connection information. Double check that the correct RancherServerURL and Token have been provided"
        exit 1
    }
}
