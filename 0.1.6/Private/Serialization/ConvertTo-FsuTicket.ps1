function ConvertTo-FsuTicket {
    <#
    .SYNOPSIS
        Maps a Freshservice ticket payload to the Q13 output contract.

    .DESCRIPTION
        Guarantees identifier, subject, status, priority, relationship IDs,
        and timestamps. Embed payloads (requester, stats, conversations)
        are copied when present and are not contractual.
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

        function Get-FsuTicketProperty {
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

        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.Ticket'
            Id = Get-FsuTicketProperty -Source $InputObject -Name 'id'
            Subject = Get-FsuTicketProperty -Source $InputObject -Name 'subject'
            Status = Get-FsuTicketProperty -Source $InputObject -Name 'status'
            Priority = Get-FsuTicketProperty -Source $InputObject -Name 'priority'
            Type = Get-FsuTicketProperty -Source $InputObject -Name 'type'
            RequesterId = Get-FsuTicketProperty -Source $InputObject -Name 'requester_id'
            ResponderId = Get-FsuTicketProperty -Source $InputObject -Name 'responder_id'
            GroupId = Get-FsuTicketProperty -Source $InputObject -Name 'group_id'
            DepartmentId = Get-FsuTicketProperty -Source $InputObject -Name 'department_id'
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuTicketProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuTicketProperty -Source $InputObject -Name 'updated_at')
            DueBy = ConvertTo-FsuUtcDateTime -Value (Get-FsuTicketProperty -Source $InputObject -Name 'due_by')
            FirstResponseDueBy = ConvertTo-FsuUtcDateTime -Value (Get-FsuTicketProperty -Source $InputObject -Name 'fr_due_by')
            Description = Get-FsuTicketProperty -Source $InputObject -Name 'description_text'
            CustomFields = Get-FsuTicketProperty -Source $InputObject -Name 'custom_fields'
            Requester = Get-FsuTicketProperty -Source $InputObject -Name 'requester'
            Stats = Get-FsuTicketProperty -Source $InputObject -Name 'stats'
            Conversations = Get-FsuTicketProperty -Source $InputObject -Name 'conversations'
        }

        $result
    }
}
