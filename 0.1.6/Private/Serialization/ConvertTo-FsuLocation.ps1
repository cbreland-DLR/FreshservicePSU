function ConvertTo-FsuLocation {
    <#
    .SYNOPSIS
        Maps a Freshservice location payload to the Q13 output contract.

    .DESCRIPTION
        Guarantees Id, Name, ParentLocationId, PrimaryContactId, CreatedAt,
        and UpdatedAt. Additional vendor fields (address, contact, primary)
        are copied as named properties when present and are not contractual.
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

        function Get-FsuLocationProperty {
            param($Source, [string]$Name)

            if ($Source -is [System.Collections.IDictionary]) {
                if ($Source.Contains($Name)) {
                    return $Source[$Name]
                }
                return $null
            }

            $property = $Source.PSObject.Properties[$Name]
            if ($null -eq $property) {
                return $null
            }
            return $property.Value
        }

        function ConvertTo-FsuUtcDateTime {
            param($Value)

            if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
                return $null
            }
            if ($Value -is [datetime]) {
                if ($Value.Kind -eq [System.DateTimeKind]::Utc) {
                    return $Value
                }
                return $Value.ToUniversalTime()
            }

            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
                return $parsed
            }
            return $null
        }

        $address = Get-FsuLocationProperty -Source $InputObject -Name 'address'

        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.Location'
            Id = Get-FsuLocationProperty -Source $InputObject -Name 'id'
            Name = Get-FsuLocationProperty -Source $InputObject -Name 'name'
            ParentLocationId = Get-FsuLocationProperty -Source $InputObject -Name 'parent_location_id'
            PrimaryContactId = Get-FsuLocationProperty -Source $InputObject -Name 'primary_contact_id'
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuLocationProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuLocationProperty -Source $InputObject -Name 'updated_at')
            Address = $address
            ContactName = Get-FsuLocationProperty -Source $InputObject -Name 'contact_name'
            Email = Get-FsuLocationProperty -Source $InputObject -Name 'email'
            Phone = Get-FsuLocationProperty -Source $InputObject -Name 'phone'
            Primary = Get-FsuLocationProperty -Source $InputObject -Name 'primary'
        }

        $result
    }
}
