function ConvertTo-FsuDepartment {
    <#
    .SYNOPSIS
        Maps a Freshservice department payload to the Q13 output contract.
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

        function Get-FsuDepartmentProperty {
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
            PSTypeName = 'FreshservicePSU.Department'
            Id = Get-FsuDepartmentProperty -Source $InputObject -Name 'id'
            Name = Get-FsuDepartmentProperty -Source $InputObject -Name 'name'
            Description = Get-FsuDepartmentProperty -Source $InputObject -Name 'description'
            HeadUserId = Get-FsuDepartmentProperty -Source $InputObject -Name 'head_user_id'
            PrimeUserId = Get-FsuDepartmentProperty -Source $InputObject -Name 'prime_user_id'
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuDepartmentProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuDepartmentProperty -Source $InputObject -Name 'updated_at')
            Domains = Get-FsuDepartmentProperty -Source $InputObject -Name 'domains'
            CustomFields = Get-FsuDepartmentProperty -Source $InputObject -Name 'custom_fields'
        }
        $result
    }
}
