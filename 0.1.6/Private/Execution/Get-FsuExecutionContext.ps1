function Get-FsuExecutionContext {
    <#
    .SYNOPSIS
        Validates the PSU boundary and builds a per-operation Freshservice.Context.

    .DESCRIPTION
        Reads trusted invocation data and FreshservicePSUConfig, validates
        configuration, normalizes identity, then resolves a credential.
        Identity validation always completes before any secret is loaded.
        The returned context is held only in the caller's local variable; it
        is never written to module, runspace, disk, or PSU-cache state.

        Tests and private callers inject Config, HostInvocation, and
        SecretResolver. Public commands omit those and use the PSU host
        adapter. This function does not accept PrincipalId, Stage, Tenant,
        AuthenticationType, or a secret value as parameters.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        $Config,

        $HostInvocation,

        [scriptblock]$SecretResolver,

        [string]$CorrelationId
    )

    function Get-FsuContextErrorRecord {
        param(
            [Parameter(Mandatory)]
            [string]$Id,

            [Parameter(Mandatory)]
            [string]$Message,

            [string]$CorrelationId
        )

        New-FsuErrorRecord -ErrorId "FreshservicePSU.Context.$Id" -Message $Message -Category InvalidOperation -CorrelationId $CorrelationId
    }

    if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
        $CorrelationId = [guid]::NewGuid().ToString('D')
    }

    if ($null -eq $HostInvocation) {
        $HostInvocation = Get-FsuHostInvocation
    }

    if ($null -eq $Config) {
        $configLookup = Get-FsuCallerVariable -Name 'FreshservicePSUConfig'
        if (-not $configLookup.Found -or $null -eq $configLookup.Value) {
            throw (Get-FsuContextErrorRecord -Id 'MissingConfiguration' -Message 'FreshservicePSUConfig is required and was not supplied by the host.' -CorrelationId $CorrelationId)
        }
        $Config = $configLookup.Value
    }

    # A 'Freshservice.Configuration' type name on $Config is not evidence that
    # the object was actually produced by Test-FsuConfiguration: $Config can
    # arrive from caller scope via Get-FsuCallerVariable, and PSTypeNames is
    # attacker-settable on any PSCustomObject (the same reasoning
    # Write-FsuAuditEvent's doc comment applies to its own trusted input).
    # Validation always runs, whether or not the type name is already present.
    $configuration = Test-FsuConfiguration -Config $Config -CorrelationId $CorrelationId

    $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation $HostInvocation -Configuration $configuration -CorrelationId $CorrelationId

    # Optional per-user secret NAME forwarded by a trusted first-party job via the
    # ambient 'FreshServiceActingSecret' variable (read from caller scope, the same
    # way identity/config are). Resolve-FsuCredential honors it only on the
    # non-interactive path, so an interactive user's validated identity always wins.
    $actingSecretLookup = Get-FsuCallerVariable -Name 'FreshServiceActingSecret'
    $actingSecretName = $null
    if ($actingSecretLookup.Found -and -not [string]::IsNullOrWhiteSpace([string]$actingSecretLookup.Value)) {
        $actingSecretName = [string]$actingSecretLookup.Value
    }

    $credential = Resolve-FsuCredential -Principal $principal -Configuration $configuration -SecretResolver $SecretResolver -ActingSecretName $actingSecretName -CorrelationId $CorrelationId

    $retryMode = if ($principal.ExecutionType -eq 'Interactive') { 'Interactive' } else { 'Noninteractive' }
    $retryPolicy = New-FsuRetryPolicy -Mode $retryMode

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.Context'
        Stage = [string]$configuration.Stage
        Tenant = [string]$configuration.Tenant
        BaseUri = [string]$configuration.BaseUri
        Principal = $principal
        Credential = $credential
        RetryPolicy = $retryPolicy
        CorrelationId = $CorrelationId
    }
}
