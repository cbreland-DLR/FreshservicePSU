function Get-FsuSecret {
    <#
    .SYNOPSIS
        Resolves a named secret to a SecureString through a provider-neutral adapter.

    .DESCRIPTION
        Configuration stores secret names only. This helper loads the value
        from an injected resolver or, when none is supplied, from
        Microsoft.PowerShell.SecretManagement Get-Secret. It never caches
        the result, never writes it to a variable outside the return, and
        never includes the secret or the secret name in error messages.
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Vault adapters may return a string. The value is wrapped as SecureString immediately and is never logged, cached, or returned as plaintext.')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [scriptblock]$Resolver,

        [string]$CorrelationId
    )

    function Get-FsuCredentialErrorRecord {
        param(
            [Parameter(Mandatory)]
            [string]$Id,

            [Parameter(Mandatory)]
            [string]$Message,

            [string]$CorrelationId
        )

        New-FsuErrorRecord -ErrorId "FreshservicePSU.Credential.$Id" -Message $Message -Category AuthenticationError -CorrelationId $CorrelationId
    }

    $result = $null
    if ($Resolver) {
        try {
            $result = & $Resolver $Name
        } catch {
            throw (Get-FsuCredentialErrorRecord -Id 'LoadFailed' -Message 'The configured credential could not be loaded.' -CorrelationId $CorrelationId)
        }
    } else {
        $getSecret = Get-Command -Name Get-Secret -ErrorAction SilentlyContinue
        if ($null -eq $getSecret) {
            throw (Get-FsuCredentialErrorRecord -Id 'ProviderUnavailable' -Message 'No secret provider is available to resolve the configured credential.' -CorrelationId $CorrelationId)
        }

        try {
            $result = Get-Secret -Name $Name -ErrorAction Stop
        } catch {
            throw (Get-FsuCredentialErrorRecord -Id 'LoadFailed' -Message 'The configured credential could not be loaded.' -CorrelationId $CorrelationId)
        }
    }

    if ($null -eq $result) {
        throw (Get-FsuCredentialErrorRecord -Id 'EmptySecret' -Message 'The configured credential was empty.' -CorrelationId $CorrelationId)
    }

    if ($result -is [securestring]) {
        if ($result.Length -le 0) {
            throw (Get-FsuCredentialErrorRecord -Id 'EmptySecret' -Message 'The configured credential was empty.' -CorrelationId $CorrelationId)
        }
        return $result
    }

    if ($result -is [pscredential]) {
        $password = $result.Password
        if ($null -eq $password -or $password.Length -le 0) {
            throw (Get-FsuCredentialErrorRecord -Id 'EmptySecret' -Message 'The configured credential was empty.' -CorrelationId $CorrelationId)
        }
        return $password
    }

    if ($result -is [string]) {
        if ([string]::IsNullOrWhiteSpace($result)) {
            throw (Get-FsuCredentialErrorRecord -Id 'EmptySecret' -Message 'The configured credential was empty.' -CorrelationId $CorrelationId)
        }
        return (ConvertTo-SecureString -String $result -AsPlainText -Force)
    }

    throw (Get-FsuCredentialErrorRecord -Id 'EmptySecret' -Message 'The configured credential was empty.' -CorrelationId $CorrelationId)
}
