function ConvertTo-FsuAssetType {
    <#
    .SYNOPSIS
        Maps a Freshservice asset-type payload to the Q13 output contract.
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

        function Get-FsuAssetTypeProperty {
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
            PSTypeName = 'FreshservicePSU.AssetType'
            Id = Get-FsuAssetTypeProperty -Source $InputObject -Name 'id'
            Name = Get-FsuAssetTypeProperty -Source $InputObject -Name 'name'
            ParentAssetTypeId = Get-FsuAssetTypeProperty -Source $InputObject -Name 'parent_asset_type_id'
            Description = Get-FsuAssetTypeProperty -Source $InputObject -Name 'description'
            Visible = Get-FsuAssetTypeProperty -Source $InputObject -Name 'visible'
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuAssetTypeProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuAssetTypeProperty -Source $InputObject -Name 'updated_at')
        }
        $result
    }
}
