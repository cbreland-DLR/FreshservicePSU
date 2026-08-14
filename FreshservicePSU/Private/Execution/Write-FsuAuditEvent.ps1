function Write-FsuAuditEvent {
    <#
    .SYNOPSIS
        Emits an already-constructed 'FreshservicePSU.AuditEvent' to the
        information stream only, tagged 'FreshservicePSU.Audit'
        (ARCHITECTURE.md §13 "Audit delivery").

    .DESCRIPTION
        This function deliberately takes the constructed event rather than
        redeclaring New-FsuAuditEvent's twelve parameters. The allowlist is
        the security contract, and a second copy of it here could drift: a
        field added to the constructor but forgotten in a pass-through
        parameter block would simply stop being recorded, silently, with no
        error. One declaration means there is nothing to keep in sync.

        A PSTypeName alone is not sufficient evidence: it is just a string a
        caller can set, and a property can be added to a legitimate event after
        construction. So the field set is verified here against the same
        allowlist the constructor builds from, immediately before emission.

        Construction and redaction therefore happen in New-FsuAuditEvent,
        before this function is reached, and the event never enters the
        success-output pipeline. Callers emit exactly one terminal event per
        attempted operation (success/failure/cancellation/uncertain); -WhatIf
        paths may use the 'Preview' outcome but must never emit 'Success'. A
        failure here must not be interpreted as operation success — it only
        records an outcome the caller already determined.

    .EXAMPLE
        New-FsuAuditEvent -CorrelationId $id -Identity $who -Stage Prod `
            -Tenant acme -CredentialType User -CredentialIdentifier $name `
            -Operation 'Get-FreshServiceTicket' -Outcome Success |
            Write-FsuAuditEvent
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('FreshservicePSU.AuditEvent')]
        $AuditEvent
    )

    process {
        $actualFields = @($AuditEvent.PSObject.Properties.Name)
        $unexpected = @($actualFields | Where-Object { $_ -notin $script:FsuAuditEventField })
        $missing = @($script:FsuAuditEventField | Where-Object { $_ -notin $actualFields })

        if ($unexpected.Count -gt 0 -or $missing.Count -gt 0) {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Audit.FieldSetMismatch' -Message 'Audit event field set does not match the allowlist; it did not come from New-FsuAuditEvent or was modified after construction.' -Category InvalidData)
        }

        Write-Information -MessageData $AuditEvent -Tags 'FreshservicePSU.Audit'
    }
}
