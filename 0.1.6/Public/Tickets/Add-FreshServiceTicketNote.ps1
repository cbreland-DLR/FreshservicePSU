function Add-FreshServiceTicketNote {
    <#
    .SYNOPSIS
        Adds a private or public note to one Freshservice ticket.

    .DESCRIPTION
        Sends POST /tickets/{id}/notes. Tenant, stage, and credentials
        come from the trusted PSU execution context. Supports
        ShouldProcess and -WhatIf. Does not send a reply, close the
        ticket, or attach files. workspace_id is not sent.

        Authorship uses the selected credential. user_id is not sent
        until Q7 sandbox evidence confirms impersonation behavior.
        POST is not retried after an uncertain delivery.

    .PARAMETER TicketId
        Freshservice ticket ID.

    .PARAMETER Body
        Note content.

    .PARAMETER Private
        When true, the note is private. Vendor default is private when
        this parameter is omitted.

    .PARAMETER NotifyEmails
        Agent or user email addresses to notify about the note.

    .EXAMPLE
        Add-FreshServiceTicketNote -TicketId 51 -Body 'Checked with the requester.' -Private $true

        Adds a private note to ticket 51.

    .OUTPUTS
        FreshservicePSU.TicketNote
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('FreshservicePSU.TicketNote')]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$TicketId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Body,

        [bool]$Private,

        [string[]]$NotifyEmails
    )

    $writeBody = @{ body = $Body }
    $bound = [System.Collections.Generic.List[string]]::new()
    $bound.Add('body')
    if ($PSBoundParameters.ContainsKey('Private')) {
        $writeBody['private'] = $Private
        $bound.Add('private')
    }
    if ($PSBoundParameters.ContainsKey('NotifyEmails')) {
        $writeBody['notify_emails'] = @($NotifyEmails)
        $bound.Add('notify_emails')
    }

    if (-not $PSCmdlet.ShouldProcess("ticket ID $TicketId", 'Add note')) {
        return
    }

    $context = Get-FsuExecutionContext
    $raw = Invoke-FsuRequest `
        -Context $context `
        -Method POST `
        -PathSegments @('tickets', [string]$TicketId, 'notes') `
        -Body $writeBody `
        -BoundParameterNames @($bound) `
        -EnvelopeProperty 'conversation' `
        -PSTypeName 'FreshservicePSU.TicketNote' `
        -Operation 'Add-FreshServiceTicketNote' `
        -ResourceId ([string]$TicketId)
    ConvertTo-FsuTicketNote -InputObject $raw -TicketId $TicketId
}
