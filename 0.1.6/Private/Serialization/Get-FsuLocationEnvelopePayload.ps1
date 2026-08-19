function Get-FsuLocationEnvelopePayload {
    <#
    .SYNOPSIS
        Extracts the location object from a single-location response body.

    .DESCRIPTION
        Freshservice documents both `location` (create) and `locations` as a
        non-array object (view). This checks those two documented names only
        and never infers an envelope from the first property.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [AllowNull()]
        $Body,

        [string]$CorrelationId
    )

    if ($null -eq $Body) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Serialization.MissingEnvelopeProperty' -Message "Response payload is missing the expected envelope property 'location'." -Category InvalidData -CorrelationId $CorrelationId -Field 'location')
    }

    $names = if ($Body -is [System.Collections.IDictionary]) {
        @($Body.Keys | ForEach-Object { [string]$_ })
    } else {
        @($Body.PSObject.Properties.Name)
    }

    $candidate = $null
    if ('location' -in $names) {
        $candidate = if ($Body -is [System.Collections.IDictionary]) { $Body['location'] } else { $Body.PSObject.Properties['location'].Value }
    } elseif ('locations' -in $names) {
        $candidate = if ($Body -is [System.Collections.IDictionary]) { $Body['locations'] } else { $Body.PSObject.Properties['locations'].Value }
        if ($candidate -is [System.Array] -or ($candidate -is [System.Collections.IList] -and $candidate -isnot [string])) {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Serialization.MissingEnvelopeProperty' -Message "Response payload 'locations' was a list; a single-location read expects one object." -Category InvalidData -CorrelationId $CorrelationId -Field 'location')
        }
    } else {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Serialization.MissingEnvelopeProperty' -Message "Response payload is missing the expected envelope property 'location'." -Category InvalidData -CorrelationId $CorrelationId -Field 'location')
    }

    return $candidate
}
