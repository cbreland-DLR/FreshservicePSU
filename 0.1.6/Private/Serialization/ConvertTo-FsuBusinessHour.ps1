function ConvertTo-FsuBusinessHour {
    <#
    .SYNOPSIS
        Maps a Freshservice business-hours payload to the Q13 output contract.
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

        function Get-FsuBusinessHourProperty {
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
            PSTypeName = 'FreshservicePSU.BusinessHour'
            Id = Get-FsuBusinessHourProperty -Source $InputObject -Name 'id'
            Name = Get-FsuBusinessHourProperty -Source $InputObject -Name 'name'
            Description = Get-FsuBusinessHourProperty -Source $InputObject -Name 'description'
            IsDefault = Get-FsuBusinessHourProperty -Source $InputObject -Name 'is_default'
            TimeZone = Get-FsuBusinessHourProperty -Source $InputObject -Name 'time_zone'
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuBusinessHourProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuBusinessHourProperty -Source $InputObject -Name 'updated_at')
            ServiceDeskHours = Get-FsuBusinessHourProperty -Source $InputObject -Name 'service_desk_hours'
            ListOfHolidays = Get-FsuBusinessHourProperty -Source $InputObject -Name 'list_of_holidays'
        }
        $result
    }
}
