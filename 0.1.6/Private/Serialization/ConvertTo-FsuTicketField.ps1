function ConvertTo-FsuTicketField {
    <#
    .SYNOPSIS
        Maps a Freshservice ticket field payload to the Q13 output contract.

    .DESCRIPTION
        Guarantees identifier, API name, display label, field type,
        required/default flags, choices, and timestamps. Nested sections
        and portal-only flags may pass through and are not contractual.
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

        function Get-FsuTicketFieldProperty {
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

        $required = Get-FsuTicketFieldProperty -Source $InputObject -Name 'required'
        if ($null -eq $required) {
            $required = Get-FsuTicketFieldProperty -Source $InputObject -Name 'required_for_agents'
        }

        $choices = Get-FsuTicketFieldProperty -Source $InputObject -Name 'choices'
        if ($null -eq $choices) {
            $choices = @()
        } else {
            $choices = @($choices)
        }

        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.TicketField'
            Id = Get-FsuTicketFieldProperty -Source $InputObject -Name 'id'
            Name = Get-FsuTicketFieldProperty -Source $InputObject -Name 'name'
            Label = Get-FsuTicketFieldProperty -Source $InputObject -Name 'label'
            FieldType = Get-FsuTicketFieldProperty -Source $InputObject -Name 'field_type'
            Required = $required
            DefaultField = Get-FsuTicketFieldProperty -Source $InputObject -Name 'default_field'
            Choices = $choices
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuTicketFieldProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuTicketFieldProperty -Source $InputObject -Name 'updated_at')
            Description = Get-FsuTicketFieldProperty -Source $InputObject -Name 'description'
            NestedFields = Get-FsuTicketFieldProperty -Source $InputObject -Name 'nested_fields'
        }

        $result
    }
}
