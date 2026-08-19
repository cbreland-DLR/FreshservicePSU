function ConvertTo-FsuRequestedItem {
    <#
    .SYNOPSIS
        Maps a Freshservice requested-item payload to the Q13 output contract.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        $InputObject,

        [long]$TicketId
    )

    process {
        if ($null -eq $InputObject) {
            return
        }

        function Get-FsuRequestedItemProperty {
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

        $payloadTicketId = Get-FsuRequestedItemProperty -Source $InputObject -Name 'ticket_id'
        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.RequestedItem'
            Id = Get-FsuRequestedItemProperty -Source $InputObject -Name 'id'
            TicketId = if ($null -ne $payloadTicketId) { $payloadTicketId } else { $TicketId }
            ServiceItemId = Get-FsuRequestedItemProperty -Source $InputObject -Name 'service_item_id'
            Quantity = Get-FsuRequestedItemProperty -Source $InputObject -Name 'quantity'
            Stage = Get-FsuRequestedItemProperty -Source $InputObject -Name 'stage'
            Loaned = Get-FsuRequestedItemProperty -Source $InputObject -Name 'loaned'
            CostPerRequest = Get-FsuRequestedItemProperty -Source $InputObject -Name 'cost_per_request'
            IsParent = Get-FsuRequestedItemProperty -Source $InputObject -Name 'is_parent'
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuRequestedItemProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuRequestedItemProperty -Source $InputObject -Name 'updated_at')
            Remarks = Get-FsuRequestedItemProperty -Source $InputObject -Name 'remarks'
            CustomFields = Get-FsuRequestedItemProperty -Source $InputObject -Name 'custom_fields'
        }
        $result
    }
}
