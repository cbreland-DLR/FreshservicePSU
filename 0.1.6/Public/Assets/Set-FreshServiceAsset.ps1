function Set-FreshServiceAsset {
    <#
    .SYNOPSIS
        Updates ordinary properties on one Freshservice asset.

    .DESCRIPTION
        Sends PUT /assets/{display_id} with only the caller-supplied
        fields. Tenant, stage, and credentials come from the trusted
        PSU execution context. Supports ShouldProcess and -WhatIf.
        Does not create, delete, restore, permanently delete, move,
        change the asset type, or send workspace_id.

        Type-specific fields are not accepted until
        Get-FreshServiceAssetType can allowlist them.

    .PARAMETER DisplayId
        Freshservice asset display ID used in the asset URL.

    .PARAMETER AssetTag
        Replacement asset tag.

    .PARAMETER Name
        Replacement display name.

    .PARAMETER Description
        Replacement description. Bind as $null to send JSON null. Accepts
        $null or a string; any other type is rejected.

    .PARAMETER UsageType
        permanent or loaner.

    .PARAMETER Impact
        low, medium, or high.

    .PARAMETER LocationId
        Location ID, or $null to clear.

    .PARAMETER DepartmentId
        Department ID, or $null to clear.

    .PARAMETER AgentId
        Assigned agent ID, or $null to clear.

    .PARAMETER UserId
        Used-by requester ID, or $null to clear.

    .PARAMETER GroupId
        Assigned group ID, or $null to clear.

    .PARAMETER AssignedOn
        Assignment timestamp, or $null to clear.

    .EXAMPLE
        Set-FreshServiceAsset -DisplayId 11 -LocationId 3 -WhatIf

        Shows the update that would be sent without calling Freshservice.

    .EXAMPLE
        Set-FreshServiceAsset -DisplayId 11 -Name 'Macbook Pro 2' -UsageType loaner

        Updates the name and usage type on asset display ID 11.

    .OUTPUTS
        FreshservicePSU.Asset
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('FreshservicePSU.Asset')]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$DisplayId,

        [ValidateNotNullOrEmpty()]
        [string]$AssetTag,

        [ValidateNotNullOrEmpty()]
        [string]$Name,

        # [object], not [string]: PowerShell converts a bound $null to ''
        # for a [string] parameter, which silently breaks the documented
        # "bind as $null to send JSON null" contract. [object] lets $null
        # bind as $null; the type is validated explicitly below and a
        # bound string is normalized to [string] before use.
        [AllowNull()]
        [object]$Description,

        [ValidateSet('permanent', 'loaner')]
        [string]$UsageType,

        [ValidateSet('low', 'medium', 'high')]
        [string]$Impact,

        [AllowNull()]
        [Nullable[long]]$LocationId,

        [AllowNull()]
        [Nullable[long]]$DepartmentId,

        [AllowNull()]
        [Nullable[long]]$AgentId,

        [AllowNull()]
        [Nullable[long]]$UserId,

        [AllowNull()]
        [Nullable[long]]$GroupId,

        [AllowNull()]
        [Nullable[datetime]]$AssignedOn
    )

    if ($PSBoundParameters.ContainsKey('Description') -and $null -ne $Description -and $Description -isnot [string]) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Asset.InvalidDescription' -Message 'Description must be a string or $null.' -Category InvalidArgument)
    }

    $vendorByParameter = [ordered]@{
        AssetTag = 'asset_tag'
        Name = 'name'
        Description = 'description'
        UsageType = 'usage_type'
        Impact = 'impact'
        LocationId = 'location_id'
        DepartmentId = 'department_id'
        AgentId = 'agent_id'
        UserId = 'user_id'
        GroupId = 'group_id'
        AssignedOn = 'assigned_on'
    }

    $body = @{}
    $boundVendorNames = [System.Collections.Generic.List[string]]::new()
    foreach ($parameterName in $vendorByParameter.Keys) {
        if (-not $PSBoundParameters.ContainsKey($parameterName)) {
            continue
        }
        $vendorName = $vendorByParameter[$parameterName]
        # PowerShell unboxes a Nullable[T] parameter at bind time: a bound
        # LocationId/AssignedOn arrives here as plain [long]/[datetime] or
        # $null (an explicit -LocationId $null), never as a boxed
        # Nullable[long]/Nullable[datetime]. No unwrap is needed -- the
        # value from $PSBoundParameters is already the concrete value or
        # $null exactly as intended for JSON null vs. omission.
        $value = $PSBoundParameters[$parameterName]
        if ($parameterName -eq 'Description' -and $null -ne $value) {
            $value = [string]$value
        }
        $body[$vendorName] = $value
        $boundVendorNames.Add($vendorName)
    }

    if ($boundVendorNames.Count -eq 0) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Asset.NoUpdateFields' -Message 'At least one updatable asset property must be supplied.' -Category InvalidArgument)
    }

    foreach ($idName in @('location_id', 'department_id', 'agent_id', 'user_id', 'group_id')) {
        if ($idName -notin $boundVendorNames) {
            continue
        }
        $idValue = $body[$idName]
        if ($null -ne $idValue -and [long]$idValue -lt 1) {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Asset.InvalidRelationshipId' -Message "The $idName value must be a positive identifier or `$null." -Category InvalidArgument)
        }
    }

    if (-not $PSCmdlet.ShouldProcess("asset display ID $DisplayId", 'Update')) {
        return
    }

    $context = Get-FsuExecutionContext
    $raw = Invoke-FsuRequest `
        -Context $context `
        -Method PUT `
        -PathSegments @('assets', [string]$DisplayId) `
        -Body $body `
        -BoundParameterNames @($boundVendorNames) `
        -EnvelopeProperty 'asset' `
        -PSTypeName 'FreshservicePSU.Asset' `
        -Operation 'Set-FreshServiceAsset' `
        -ResourceId ([string]$DisplayId)
    ConvertTo-FsuAsset -InputObject $raw
}
