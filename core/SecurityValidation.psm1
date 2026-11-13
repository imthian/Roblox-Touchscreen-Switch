# Roblox Touchscreen Switch - Shared Security & Permission Validation Module (v1.2.4)

$R = [System.Security.AccessControl.FileSystemRights]
# Write-only rights (0xD0156) plus GenericWrite (0x40000000) and GenericAll (0x10000000) = 0x500D0156
# ReadAndExecute (0x1200A9) has ZERO overlap: 0x1200A9 -band 0x500D0156 = 0.
$script:WriteRightsMask = [int]($R::WriteData -bor $R::AppendData -bor $R::WriteExtendedAttributes -bor `
                               $R::WriteAttributes -bor $R::DeleteSubdirectoriesAndFiles -bor `
                               $R::Delete -bor $R::ChangePermissions -bor $R::TakeOwnership -bor `
                               0x40000000 -bor 0x10000000)

$script:SidSystem = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
$script:SidAdmins = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')

function Test-SafeDirectoryAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.AccessControl.DirectorySecurity]$DirectoryAcl,
        [string]$PathDescription = "Directory"
    )

    $OwnerSid = $DirectoryAcl.GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($OwnerSid -ne $script:SidSystem -and $OwnerSid -ne $script:SidAdmins) {
        return @{
            Success = $false
            Error = "$PathDescription is owned by untrusted SID '$($OwnerSid.Value)'."
        }
    }

    $AccessRules = $DirectoryAcl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
    foreach ($rule in $AccessRules) {
        if ($rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
            $HasWrite = ([int]$rule.FileSystemRights -band $script:WriteRightsMask) -ne 0
            if ($HasWrite) {
                $RuleSid = [System.Security.Principal.SecurityIdentifier]$rule.IdentityReference
                if ($RuleSid -ne $script:SidSystem -and $RuleSid -ne $script:SidAdmins) {
                    return @{
                        Success = $false
                        Error = "$PathDescription grants write/modify rights to untrusted SID '$($RuleSid.Value)'."
                    }
                }
            }
        }
    }

    return @{ Success = $true; Error = $null }
}

function Get-WriteRightsMask {
    return $script:WriteRightsMask
}

Export-ModuleMember -Function Test-SafeDirectoryAcl, Get-WriteRightsMask
