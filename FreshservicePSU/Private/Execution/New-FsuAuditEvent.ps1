# The audit allowlist, declared once. New-FsuAuditEvent builds from it and
# Write-FsuAuditEvent verifies against it, so the closed field set has exactly
# one definition (ARCHITECTURE.md §13).
$script:FsuAuditEventField = @(
    'CorrelationId'
    'Identity'
    'Stage'
    'Tenant'
    'CredentialType'
    'CredentialIdentifier'
    'Operation'
    'ResourceId'
    'Outcome'
    'Status'
    'FallbackUsed'
    'RateLimitState'
)

function New-FsuAuditEvent {
    <#
    .SYNOPSIS
        Builds a 'FreshservicePSU.AuditEvent' object from a closed allowlist
        of fields (ARCHITECTURE.md §13 + "Audit delivery").

    .DESCRIPTION
        The object is built entirely from explicit named parameters, never by
        copying an input hashtable and deleting keys, so a caller cannot
        smuggle an unlisted field onto the event by construction. The
        allowlist is exactly: correlation ID, PSU identity, stage, tenant,
        credential type, non-secret credential identifier, operation,
        resource ID, outcome, status, fallback use, and rate-limit state.

        This function only constructs and redacts; it performs no stream
        output. Use Write-FsuAuditEvent to emit the constructed object to the
        information stream.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory object constructor; no system state is changed.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialType and CredentialIdentifier are non-secret labels (a mode and a vault secret NAME), never a secret value; ARCHITECTURE.md §13 explicitly allows these on the audit allowlist.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$CorrelationId,

        [Parameter(Mandatory)]
        [string]$Identity,

        [Parameter(Mandatory)]
        [ValidateSet('Prod', 'Dev')]
        [string]$Stage,

        [Parameter(Mandatory)]
        [string]$Tenant,

        [Parameter(Mandatory)]
        [ValidateSet('User', 'System')]
        [string]$CredentialType,

        [Parameter(Mandatory)]
        [string]$CredentialIdentifier,

        [Parameter(Mandatory)]
        [string]$Operation,

        [string]$ResourceId,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failure', 'Cancellation', 'Uncertain', 'Preview')]
        [string]$Outcome,

        [Nullable[int]]$Status,

        [bool]$FallbackUsed = $false,

        [string]$RateLimitState
    )

    return [PSCustomObject]@{
        PSTypeName = 'FreshservicePSU.AuditEvent'
        CorrelationId = $CorrelationId
        Identity = $Identity
        Stage = $Stage
        Tenant = $Tenant
        CredentialType = $CredentialType
        CredentialIdentifier = $CredentialIdentifier
        Operation = $Operation
        ResourceId = $ResourceId
        Outcome = $Outcome
        Status = $Status
        FallbackUsed = $FallbackUsed
        RateLimitState = $RateLimitState
    }
}
