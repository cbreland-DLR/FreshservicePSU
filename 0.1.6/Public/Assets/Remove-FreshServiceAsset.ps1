function Remove-FreshServiceAsset {
    <#
    .SYNOPSIS
        Soft-deletes one Freshservice asset.

    .DESCRIPTION
        Sends DELETE /assets/{display_id}. Tenant, stage, and credentials
        come from the trusted PSU execution context. Supports ShouldProcess
        and -WhatIf. ConfirmImpact is High.

        This is the vendor trash operation, not a permanent delete.
        Restore, delete-forever, and workspace moves are out of scope.
        workspace_id is not sent. No output is written on success.

    .PARAMETER DisplayId
        Freshservice asset display ID used in the asset URL.

    .EXAMPLE
        Remove-FreshServiceAsset -DisplayId 11 -WhatIf

        Shows the delete that would be sent without calling Freshservice.

    .EXAMPLE
        Remove-FreshServiceAsset -DisplayId 11

        Moves asset display ID 11 to trash.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$DisplayId
    )

    if (-not $PSCmdlet.ShouldProcess("asset display ID $DisplayId", 'Remove')) {
        return
    }

    $context = Get-FsuExecutionContext
    $null = Invoke-FsuRequest `
        -Context $context `
        -Method DELETE `
        -PathSegments @('assets', [string]$DisplayId) `
        -Operation 'Remove-FreshServiceAsset' `
        -ResourceId ([string]$DisplayId)
}
