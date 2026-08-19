function ConvertTo-FsuRequester {
    <#
    .SYNOPSIS
        Maps a Freshservice requester payload to the Q13 output contract.
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

        function Get-FsuRequesterProperty {
            param($Source, [string]$Name)
            if ($Source -is [System.Collections.IDictionary]) {
                if ($Source.Contains($Name)) { return $Source[$Name] }
                return $null
            }
            $property = $Source.PSObject.Properties[$Name]
            if ($null -eq $property) { return $null }
            return $property.Value
        }

        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.Requester'
            Id = Get-FsuRequesterProperty -Source $InputObject -Name 'id'
            FirstName = Get-FsuRequesterProperty -Source $InputObject -Name 'first_name'
            LastName = Get-FsuRequesterProperty -Source $InputObject -Name 'last_name'
            Email = Get-FsuRequesterProperty -Source $InputObject -Name 'primary_email'
            Active = Get-FsuRequesterProperty -Source $InputObject -Name 'active'
            JobTitle = Get-FsuRequesterProperty -Source $InputObject -Name 'job_title'
            DepartmentIds = Get-FsuRequesterProperty -Source $InputObject -Name 'department_ids'
            LocationId = Get-FsuRequesterProperty -Source $InputObject -Name 'location_id'
            ReportingManagerId = Get-FsuRequesterProperty -Source $InputObject -Name 'reporting_manager_id'
            IsAgent = Get-FsuRequesterProperty -Source $InputObject -Name 'is_agent'
        }
        $result
    }
}
