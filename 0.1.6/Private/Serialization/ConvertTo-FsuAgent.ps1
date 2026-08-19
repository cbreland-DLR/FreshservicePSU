function ConvertTo-FsuAgent {
    <#
    .SYNOPSIS
        Maps a Freshservice agent payload to the Q13 output contract.
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

        function Get-FsuAgentProperty {
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
            PSTypeName = 'FreshservicePSU.Agent'
            Id = Get-FsuAgentProperty -Source $InputObject -Name 'id'
            FirstName = Get-FsuAgentProperty -Source $InputObject -Name 'first_name'
            LastName = Get-FsuAgentProperty -Source $InputObject -Name 'last_name'
            Email = Get-FsuAgentProperty -Source $InputObject -Name 'email'
            Active = Get-FsuAgentProperty -Source $InputObject -Name 'active'
            Occasional = Get-FsuAgentProperty -Source $InputObject -Name 'occasional'
            JobTitle = Get-FsuAgentProperty -Source $InputObject -Name 'job_title'
            DepartmentIds = Get-FsuAgentProperty -Source $InputObject -Name 'department_ids'
            LocationId = Get-FsuAgentProperty -Source $InputObject -Name 'location_id'
            ReportingManagerId = Get-FsuAgentProperty -Source $InputObject -Name 'reporting_manager_id'
            LastLoginAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuAgentProperty -Source $InputObject -Name 'last_login_at')
            MemberOf = Get-FsuAgentProperty -Source $InputObject -Name 'member_of'
        }
        $result
    }
}
