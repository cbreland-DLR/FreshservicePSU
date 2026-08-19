function ConvertTo-FsuSLAPolicy {
    <#
    .SYNOPSIS
        Maps a Freshservice SLA-policy payload to the Q13 output contract.
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

        function Get-FsuSLAPolicyProperty {
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
            PSTypeName = 'FreshservicePSU.SLAPolicy'
            Id = Get-FsuSLAPolicyProperty -Source $InputObject -Name 'id'
            Name = Get-FsuSLAPolicyProperty -Source $InputObject -Name 'name'
            Position = Get-FsuSLAPolicyProperty -Source $InputObject -Name 'position'
            IsDefault = Get-FsuSLAPolicyProperty -Source $InputObject -Name 'is_default'
            Active = Get-FsuSLAPolicyProperty -Source $InputObject -Name 'active'
            Deleted = Get-FsuSLAPolicyProperty -Source $InputObject -Name 'deleted'
            Description = Get-FsuSLAPolicyProperty -Source $InputObject -Name 'description'
            SlaTargets = Get-FsuSLAPolicyProperty -Source $InputObject -Name 'sla_targets'
            ApplicableTo = Get-FsuSLAPolicyProperty -Source $InputObject -Name 'applicable_to'
        }
        $result
    }
}
