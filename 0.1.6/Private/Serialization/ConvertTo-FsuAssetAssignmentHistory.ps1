function ConvertTo-FsuAssetAssignmentHistory {
    <#
    .SYNOPSIS
        Maps a Freshservice asset assignment-history payload to the Q13 contract.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        $InputObject,

        [long]$DisplayId
    )

    process {
        if ($null -eq $InputObject) {
            return
        }

        function Get-FsuAssignmentHistoryProperty {
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

        $payloadDisplayId = Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'display_id'
        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.AssetAssignmentHistory'
            Id = Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'id'
            DisplayId = if ($null -ne $payloadDisplayId) { $payloadDisplayId } else { $DisplayId }
            UserId = Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'user_id'
            UserName = Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'user_name'
            AssignedOn = ConvertTo-FsuUtcDateTime -Value (Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'assigned_on')
            AssignedBy = Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'assigned_by'
            AssignedByName = Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'assigned_by_name'
            UnassignedBy = Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'unassigned_by'
            UnassignedByName = Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'unassigned_by_name'
            UnassignedOn = ConvertTo-FsuUtcDateTime -Value (Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'unassigned_on')
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuAssignmentHistoryProperty -Source $InputObject -Name 'updated_at')
        }
        $result
    }
}
