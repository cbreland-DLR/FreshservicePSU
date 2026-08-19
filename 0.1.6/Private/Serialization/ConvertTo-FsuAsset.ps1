function ConvertTo-FsuAsset {
    <#
    .SYNOPSIS
        Maps a Freshservice asset payload to the Q13 output contract.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        $InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return
        }

        function Get-FsuAssetProperty {
            param($Source, [string]$Name)
            if ($Source -is [System.Collections.IDictionary]) {
                if ($Source.Contains($Name)) { return $Source[$Name] }
                return $null
            }
            $property = $Source.PSObject.Properties[$Name]
            if ($null -eq $property) { return $null }
            return $property.Value
        }

        function ConvertTo-FsuUtcDateTime {
            param($Value)
            if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) { return $null }
            if ($Value -is [datetime]) {
                if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value }
                return $Value.ToUniversalTime()
            }
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
                return $parsed
            }
            return $null
        }

        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.Asset'
            Id = Get-FsuAssetProperty -Source $InputObject -Name 'id'
            DisplayId = Get-FsuAssetProperty -Source $InputObject -Name 'display_id'
            Name = Get-FsuAssetProperty -Source $InputObject -Name 'name'
            AssetTag = Get-FsuAssetProperty -Source $InputObject -Name 'asset_tag'
            AssetTypeId = Get-FsuAssetProperty -Source $InputObject -Name 'asset_type_id'
            UsageType = Get-FsuAssetProperty -Source $InputObject -Name 'usage_type'
            Impact = Get-FsuAssetProperty -Source $InputObject -Name 'impact'
            LocationId = Get-FsuAssetProperty -Source $InputObject -Name 'location_id'
            DepartmentId = Get-FsuAssetProperty -Source $InputObject -Name 'department_id'
            AgentId = Get-FsuAssetProperty -Source $InputObject -Name 'agent_id'
            UserId = Get-FsuAssetProperty -Source $InputObject -Name 'user_id'
            GroupId = Get-FsuAssetProperty -Source $InputObject -Name 'group_id'
            AssignedOn = ConvertTo-FsuUtcDateTime -Value (Get-FsuAssetProperty -Source $InputObject -Name 'assigned_on')
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuAssetProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuAssetProperty -Source $InputObject -Name 'updated_at')
            Description = Get-FsuAssetProperty -Source $InputObject -Name 'description'
            TypeFields = Get-FsuAssetProperty -Source $InputObject -Name 'type_fields'
        }
        $result
    }
}
