function ConvertTo-FsuTicketActivity {
    <#
    .SYNOPSIS
        Maps a Freshservice ticket-activity payload to the Q13 output contract.
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

        function Get-FsuActivityProperty {
            param($Source, [string]$Name)
            if ($null -eq $Source) { return $null }
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

        $actor = Get-FsuActivityProperty -Source $InputObject -Name 'actor'
        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.TicketActivity'
            TicketId = $TicketId
            ActorId = Get-FsuActivityProperty -Source $actor -Name 'id'
            ActorName = Get-FsuActivityProperty -Source $actor -Name 'name'
            Content = Get-FsuActivityProperty -Source $InputObject -Name 'content'
            SubContents = Get-FsuActivityProperty -Source $InputObject -Name 'sub_contents'
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuActivityProperty -Source $InputObject -Name 'created_at')
        }
        $result
    }
}
