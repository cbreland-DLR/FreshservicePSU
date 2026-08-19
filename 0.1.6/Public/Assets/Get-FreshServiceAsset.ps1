function Get-FreshServiceAsset {
    <#
    .SYNOPSIS
        Gets one Freshservice asset or a bounded filtered asset list.

    .DESCRIPTION
        Reads assets for PSU pages, automations, and reporting. Tenant,
        stage, and credentials come from the trusted PSU execution
        context. Does not create, update, delete, restore, move, or
        reach components, requests, contracts, or relationships.
        workspace_id is not sent.

        -DisplayId uses GET /assets/{display_id}. -AssetTag and
        -SerialNumber are exact lookups through GET /assets?filter=.
        -Filter is a bounded validated vendor filter on the same
        endpoint. There is no unbounded list.

    .PARAMETER DisplayId
        Freshservice asset display ID used in the asset URL.

    .PARAMETER AssetTag
        Exact asset tag lookup.

    .PARAMETER SerialNumber
        Exact serial number lookup.

    .PARAMETER Filter
        Freshservice asset filter expression without surrounding
        double quotes. Rejected when empty, unbounded, malformed,
        overlong, or when it selects workspace_id.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 30, matching the filter endpoint.

    .PARAMETER MaxRecords
        Maximum records to emit for a filter or identifier list.
        Default 1000.

    .EXAMPLE
        Get-FreshServiceAsset -DisplayId 11

        Returns one asset for a PSU detail page.

    .EXAMPLE
        Get-FreshServiceAsset -AssetTag 'ASSET-9'

        Returns the asset with that tag.

    .EXAMPLE
        Get-FreshServiceAsset -Filter "asset_state:'IN STOCK' AND location_id:3"

        Streams in-stock assets at location 3.

    .OUTPUTS
        FreshservicePSU.Asset
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType('FreshservicePSU.Asset')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'DisplayId')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$DisplayId,

        [Parameter(Mandatory, ParameterSetName = 'AssetTag')]
        [ValidateNotNullOrEmpty()]
        [string]$AssetTag,

        [Parameter(Mandatory, ParameterSetName = 'SerialNumber')]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,

        [Parameter(Mandatory, ParameterSetName = 'Filter')]
        [string]$Filter,

        [Parameter(ParameterSetName = 'AssetTag')]
        [Parameter(ParameterSetName = 'SerialNumber')]
        [Parameter(ParameterSetName = 'Filter')]
        [ValidateRange(1, 100)]
        [int]$PerPage = 30,

        [Parameter(ParameterSetName = 'AssetTag')]
        [Parameter(ParameterSetName = 'SerialNumber')]
        [Parameter(ParameterSetName = 'Filter')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    $context = Get-FsuExecutionContext
    $common = @{
        Context = $context
        Operation = 'Get-FreshServiceAsset'
    }

    if ($PSCmdlet.ParameterSetName -eq 'DisplayId') {
        $raw = Invoke-FsuRequest @common `
            -Method GET `
            -PathSegments @('assets', [string]$DisplayId) `
            -EnvelopeProperty 'asset' `
            -PSTypeName 'FreshservicePSU.Asset' `
            -ResourceId ([string]$DisplayId)
        ConvertTo-FsuAsset -InputObject $raw
        return
    }

    $filterText = switch ($PSCmdlet.ParameterSetName) {
        'AssetTag' { "asset_tag:'{0}'" -f ($AssetTag -replace "'", "''") }
        'SerialNumber' { "serial_number:'{0}'" -f ($SerialNumber -replace "'", "''") }
        default { $Filter }
    }
    $normalizedFilter = Test-FsuAssetFilterQuery -Query $filterText -CorrelationId ([string]$context.CorrelationId)

    Invoke-FsuNumberedPagedRequest @common `
        -PathSegments @('assets') `
        -QueryParameters @{ filter = ('"{0}"' -f $normalizedFilter) } `
        -EnvelopeProperty 'assets' `
        -PSTypeName 'FreshservicePSU.Asset' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords |
        ConvertTo-FsuAsset
}
