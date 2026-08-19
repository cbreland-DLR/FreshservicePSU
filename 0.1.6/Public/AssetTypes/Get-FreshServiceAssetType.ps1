function Get-FreshServiceAssetType {
    <#
    .SYNOPSIS
        Gets one Freshservice asset type or a bounded asset-type list.

    .DESCRIPTION
        Reads asset types for PSU asset forms, filters, and validation.
        Tenant, stage, and credentials come from the trusted PSU
        execution context. Does not create, update, or delete types.
        Asset-type fields are a different resource and are not selected
        through a mode switch. workspace_id is not sent.

        -Id uses GET /asset_types/{id}. A list call uses GET /asset_types
        and streams pages until MaxRecords is reached. Asset-type data
        is cache-eligible; the shared reference cache is not yet wired.

    .PARAMETER Id
        Freshservice asset-type ID.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit for a list. Default 1000.

    .EXAMPLE
        Get-FreshServiceAssetType -Id 50

        Returns the Chromebook asset type for a form choice.

    .EXAMPLE
        Get-FreshServiceAssetType -MaxRecords 50

        Streams asset types for a filter list.

    .OUTPUTS
        FreshservicePSU.AssetType
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.AssetType')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, 100)]
        [int]$PerPage = 100,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    $context = Get-FsuExecutionContext
    $common = @{
        Context = $context
        Operation = 'Get-FreshServiceAssetType'
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $raw = Invoke-FsuRequest @common `
            -Method GET `
            -PathSegments @('asset_types', [string]$Id) `
            -EnvelopeProperty 'asset_type' `
            -PSTypeName 'FreshservicePSU.AssetType' `
            -ResourceId ([string]$Id)
        ConvertTo-FsuAssetType -InputObject $raw
        return
    }

    Invoke-FsuPagedRequest @common `
        -PathSegments @('asset_types') `
        -EnvelopeProperty 'asset_types' `
        -PSTypeName 'FreshservicePSU.AssetType' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords |
        ConvertTo-FsuAssetType
}
