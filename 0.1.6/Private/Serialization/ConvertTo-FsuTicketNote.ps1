function ConvertTo-FsuTicketNote {
    <#
    .SYNOPSIS
        Maps a Freshservice conversation/note payload to the Q13 contract.
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

        function Get-FsuTicketNoteProperty {
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

        $payloadTicketId = Get-FsuTicketNoteProperty -Source $InputObject -Name 'ticket_id'
        $bodyText = Get-FsuTicketNoteProperty -Source $InputObject -Name 'body_text'
        if ($null -eq $bodyText) {
            $bodyText = Get-FsuTicketNoteProperty -Source $InputObject -Name 'body'
        }
        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.TicketNote'
            Id = Get-FsuTicketNoteProperty -Source $InputObject -Name 'id'
            TicketId = if ($null -ne $payloadTicketId) { $payloadTicketId } else { $TicketId }
            Body = $bodyText
            Private = Get-FsuTicketNoteProperty -Source $InputObject -Name 'private'
            UserId = Get-FsuTicketNoteProperty -Source $InputObject -Name 'user_id'
            Incoming = Get-FsuTicketNoteProperty -Source $InputObject -Name 'incoming'
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuTicketNoteProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuTicketNoteProperty -Source $InputObject -Name 'updated_at')
        }
        $result
    }
}
