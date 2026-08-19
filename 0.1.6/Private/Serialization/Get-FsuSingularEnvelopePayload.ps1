function Get-FsuSingularEnvelopePayload {
    <#
    .SYNOPSIS
        Extracts one object from a documented singular envelope name.

    .DESCRIPTION
        Checks -PrimaryName first, then -AlternateName when the vendor
        documents both (for example department vs departments as an object).
        A list under the alternate name is rejected. Does not infer an
        envelope from the first property.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [AllowNull()]
        $Body,

        [Parameter(Mandatory)]
        [string]$PrimaryName,

        [string]$AlternateName,

        [string]$CorrelationId
    )

    if ($null -eq $Body) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Serialization.MissingEnvelopeProperty' -Message "Response payload is missing the expected envelope property '$PrimaryName'." -Category InvalidData -CorrelationId $CorrelationId -Field $PrimaryName)
    }

    $names = if ($Body -is [System.Collections.IDictionary]) {
        @($Body.Keys | ForEach-Object { [string]$_ })
    } else {
        @($Body.PSObject.Properties.Name)
    }

    function Get-FsuEnvelopeValue {
        param($Source, [string]$Name)
        if ($Source -is [System.Collections.IDictionary]) {
            return $Source[$Name]
        }
        return $Source.PSObject.Properties[$Name].Value
    }

    if ($PrimaryName -in $names) {
        return Get-FsuEnvelopeValue -Source $Body -Name $PrimaryName
    }

    if ($AlternateName -and $AlternateName -in $names) {
        $candidate = Get-FsuEnvelopeValue -Source $Body -Name $AlternateName
        if ($candidate -is [System.Array] -or ($candidate -is [System.Collections.IList] -and $candidate -isnot [string])) {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Serialization.MissingEnvelopeProperty' -Message "Response payload '$AlternateName' was a list; a single-object read expects one object." -Category InvalidData -CorrelationId $CorrelationId -Field $PrimaryName)
        }
        return $candidate
    }

    throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Serialization.MissingEnvelopeProperty' -Message "Response payload is missing the expected envelope property '$PrimaryName'." -Category InvalidData -CorrelationId $CorrelationId -Field $PrimaryName)
}
