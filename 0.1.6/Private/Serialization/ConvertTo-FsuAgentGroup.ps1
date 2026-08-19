function ConvertTo-FsuAgentGroup {
    <#
    .SYNOPSIS
        Maps a Freshservice agent group payload to the Q13 output contract.
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

        function Get-FsuAgentGroupProperty {
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
            PSTypeName = 'FreshservicePSU.AgentGroup'
            Id = Get-FsuAgentGroupProperty -Source $InputObject -Name 'id'
            Name = Get-FsuAgentGroupProperty -Source $InputObject -Name 'name'
            Description = Get-FsuAgentGroupProperty -Source $InputObject -Name 'description'
            Restricted = Get-FsuAgentGroupProperty -Source $InputObject -Name 'restricted'
            EscalateTo = Get-FsuAgentGroupProperty -Source $InputObject -Name 'escalate_to'
            BusinessHoursId = Get-FsuAgentGroupProperty -Source $InputObject -Name 'business_hours_id'
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuAgentGroupProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuAgentGroupProperty -Source $InputObject -Name 'updated_at')
            Members = Get-FsuAgentGroupProperty -Source $InputObject -Name 'members'
            Leaders = Get-FsuAgentGroupProperty -Source $InputObject -Name 'leaders'
        }
        $result
    }
}
