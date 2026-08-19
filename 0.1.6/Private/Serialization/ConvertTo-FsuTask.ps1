function ConvertTo-FsuTask {
    <#
    .SYNOPSIS
        Maps a Freshservice ticket-task payload to the Q13 output contract.
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

        function Get-FsuTaskProperty {
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

        $payloadTicketId = Get-FsuTaskProperty -Source $InputObject -Name 'ticket_id'
        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.Task'
            Id = Get-FsuTaskProperty -Source $InputObject -Name 'id'
            TicketId = if ($null -ne $payloadTicketId) { $payloadTicketId } else { $TicketId }
            Title = Get-FsuTaskProperty -Source $InputObject -Name 'title'
            Status = Get-FsuTaskProperty -Source $InputObject -Name 'status'
            AgentId = Get-FsuTaskProperty -Source $InputObject -Name 'agent_id'
            GroupId = Get-FsuTaskProperty -Source $InputObject -Name 'group_id'
            DueDate = ConvertTo-FsuUtcDateTime -Value (Get-FsuTaskProperty -Source $InputObject -Name 'due_date')
            ClosedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuTaskProperty -Source $InputObject -Name 'closed_at')
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuTaskProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuTaskProperty -Source $InputObject -Name 'updated_at')
            Description = Get-FsuTaskProperty -Source $InputObject -Name 'description'
        }
        $result
    }
}
