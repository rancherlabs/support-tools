# Securing file ACLs on RKE2 Windows nodes

In certain cases, Windows nodes joined to RKE2 clusters may not have appropriate Access Control Lists (ACLs) configured for important files and directories, allowing improper access by unprivileged user accounts such as `NT AUTHORITY\Authenticated Users`. This occurs in the following configurations

+ Standalone RKE2 nodes (i.e. RKE2 nodes **_not_** provisioned using Rancher) which run on Windows that were _initially_ provisioned using a version older than `1.27.15`, `1.28.11`, `1.29.6`, or `1.30.2`

+ Rancher provisioned RKE2 nodes that run on Windows that were created using a Rancher version older than `2.9.3` or `2.8.9`.

This issue has been resolved for standalone RKE2 clusters starting with versions `1.27.15`, `1.28.1`, `1.29.6`, `1.30.2` and above. Rancher `2.9.3`, `2.8.9`, and above, have also been updated to properly configure ACLs on Windows nodes during initial provisioning as well as to retroactively update ACLs on existing nodes.

If you are maintaining a standalone RKE2 Windows cluster which was provisioned using a version of RKE2 older than `1.27.15`, `1.28.11`, `1.29.6`, `1.30.2`, or if you maintain a Rancher provisioned RKE2 Windows cluster but are unable to upgrade to at least `2.9.3` or `2.8.9`, then you can use the below powershell script to manually update the relevant ACLs.

This script only needs to be run once per node. If desired, additional files and directories can be secured by updating the `$restrictedPaths` variable. After running the script, only the `NT AUTHORITY\SYSTEM` and `BUILTIN\Administrators` group will have access to the specified files and directories. Directories will be configured with inheritance enabled to ensure child files and directories utilize the same restrictive ACL.

Add the below script to a PowerShell file and run it using the PowerShell console as an Administrator.

```powershell
function Set-RestrictedPermissions {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Path,
        [Parameter(Mandatory=$true)]
        [Boolean]
        $Directory
    )
    $Owner = "BUILTIN\Administrators"
    $Group = "NT AUTHORITY\SYSTEM"
    $acl = Get-Acl $Path
    
    foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        $acl.RemoveAccessRule($rule) | Out-Null
    }
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner((New-Object System.Security.Principal.NTAccount($Owner)))
    $acl.SetGroup((New-Object System.Security.Principal.NTAccount($Group)))
    
    Set-FileSystemAccessRule -Directory $Directory -acl $acl

    $FullPath = Resolve-Path $Path
    Write-Host "Setting restricted ACL on $FullPath"
    Set-Acl -Path $Path -AclObject $acl
}

function Set-FileSystemAccessRule() {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [Boolean]
        $Directory,
        [Parameter(Mandatory=$false)]
        [System.Security.AccessControl.ObjectSecurity]
        $acl
    )
    $users = @(
        $acl.Owner,
        $acl.Group
    )
    if ($Directory -eq $true) {
        foreach ($user in $users) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $user,
                [System.Security.AccessControl.FileSystemRights]::FullControl,
                [System.Security.AccessControl.InheritanceFlags]'ObjectInherit,ContainerInherit',
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            $acl.AddAccessRule($rule)
        }
    } else {
        foreach ($user in $users) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $user,
                [System.Security.AccessControl.FileSystemRights]::FullControl,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            $acl.AddAccessRule($rule)
        }
    }
}

function Confirm-ACL { 
	[CmdletBinding()]
	param (
		[Parameter(Mandatory=$true)]
		[String]
		$Path
	)
	foreach ($a in (Get-Acl $path).Access) {
		$ref = $a.IdentityReference
		if (($ref -ne "BUILTIN\Administrators") -and ($ref -ne "NT AUTHORITY\SYSTEM")) { 
			return $false
		}
	}
	return $true
}

$RKE2_DATA_DIR="c:\var\lib\rancher\rke2"
$SYSTEM_AGENT_DIR="c:\var\lib\rancher\agent"
$RANCHER_PROVISIONING_DIR="c:\var\lib\rancher\capr"

$restrictedPaths = @(
    [PSCustomObject]@{
        Path = "c:\etc\rancher\wins\config"
        Directory = $false
    }
    [PSCustomObject]@{
        Path = "c:\etc\rancher\node\password"
        Directory = $false
    }
    [PSCustomObject]@{
        Path = "$SYSTEM_AGENT_DIR\rancher2_connection_info.json"
        Directory = $false
    }
    [PSCustomObject]@{
        Path = "c:\etc\rancher\rke2\config.yaml.d\50-rancher.yaml"
        Directory = $false
    }
    [PSCustomObject]@{
        Path = "c:\usr\local\bin\rke2.exe"
        Directory = $false
    }
    [PSCustomObject]@{
        Path = "$RANCHER_PROVISIONING_DIR"
        Directory = $true
    }
    [PSCustomObject]@{
        Path = "$SYSTEM_AGENT_DIR"
        Directory = $true
    }
    [PSCustomObject]@{
        Path = "$RKE2_DATA_DIR"
        Directory = $true
    }
)

foreach ($path in $restrictedPaths) {
    # Some paths will not exist on standalone RKE2 clusters
    if (-Not (Test-Path -Path $path.Path)) {
        continue
    }
    
    if (-Not (Confirm-ACL -Path $path.Path)) {
        Set-RestrictedPermissions -Path $path.Path -Directory $path.Directory
    } else { 
        Write-Host "ACLs have been properly configured for the $($path.Path) $(if($path.Directory){ "directory" } else { "file" })"
    }
}
```
