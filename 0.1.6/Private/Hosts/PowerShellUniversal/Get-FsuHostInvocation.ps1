function Get-FsuHostInvocation {
    <#
    .SYNOPSIS
        Snapshots trusted PowerShell Universal invocation values.

    .DESCRIPTION
        Reads only the documented PSU automatic variables ($ClaimsPrincipal,
        $Identity, $User, $Roles, $UAJob). It does not accept identity,
        issuer, stage, tenant, or authentication type from command
        parameters. A session with none of those variables returns Surface
        Unknown and empty identity fields; callers fail closed.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $claims = Get-FsuCallerVariable -Name 'ClaimsPrincipal'
    $identity = Get-FsuCallerVariable -Name 'Identity'
    $user = Get-FsuCallerVariable -Name 'User'
    $roles = Get-FsuCallerVariable -Name 'Roles'
    $job = Get-FsuCallerVariable -Name 'UAJob'

    $jobIdentityName = $null
    if ($job.Found -and $null -ne $job.Value) {
        $jobValue = $job.Value
        if ($jobValue.PSObject.Properties['Identity'] -and $null -ne $jobValue.Identity) {
            $jobIdentity = $jobValue.Identity
            if ($jobIdentity.PSObject.Properties['Name']) {
                $jobIdentityName = [string]$jobIdentity.Name
            }
        }
    }

    $roleValues = @()
    if ($roles.Found -and $null -ne $roles.Value) {
        $roleValues = @($roles.Value | ForEach-Object { [string]$_ })
    }

    $surface = 'Unknown'
    if ($job.Found) {
        $surface = 'Schedule'
    } elseif ($user.Found) {
        $surface = 'App'
    } elseif ($identity.Found) {
        $surface = 'Api'
    }

    $claimsPrincipal = $null
    if ($claims.Found) {
        $claimsPrincipal = $claims.Value
    }

    $identityValue = $null
    if ($identity.Found) {
        $identityValue = $identity.Value
    }

    $userValue = $null
    if ($user.Found) {
        $userValue = $user.Value
    }

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.HostInvocation'
        Surface = $surface
        Identity = $identityValue
        User = $userValue
        ClaimsPrincipal = $claimsPrincipal
        JobIdentityName = $jobIdentityName
        Roles = $roleValues
    }
}
