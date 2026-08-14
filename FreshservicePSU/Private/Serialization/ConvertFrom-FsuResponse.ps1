function ConvertFrom-FsuResponse {
    <#
    .SYNOPSIS
        Extracts a named envelope property from an already-parsed response
        payload and applies a PSTypeName (ARCHITECTURE.md §10, §11).

    .DESCRIPTION
        Deserialization of the raw payload is the caller's responsibility;
        this takes already-parsed content plus the envelope property name to
        extract. The envelope property must be named EXPLICITLY by the
        caller and is never inferred from the first property of the payload,
        because Freshservice may add attributes with no notice (§11 "Vendor
        change policy") and inference would silently change what a command
        returns. A payload missing the expected envelope property is a
        terminating error, not an empty result. A $null Body passes through
        unchanged. Embedded ('include') properties keep the same PSTypeName
        and are extracted by name exactly like any other property.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory extraction; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Body,

        [Parameter(Mandatory)]
        [string]$EnvelopeProperty,

        [Parameter(Mandatory)]
        [string]$PSTypeName,

        [string]$CorrelationId
    )

    if ($null -eq $Body) {
        return $null
    }

    $propertyNames = @()
    if ($Body -is [System.Collections.IDictionary]) {
        $propertyNames = @($Body.Keys)
    } else {
        $propertyNames = @($Body.PSObject.Properties.Name)
    }

    if ($EnvelopeProperty -notin $propertyNames) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Serialization.MissingEnvelopeProperty' -Message "Response payload is missing the expected envelope property '$EnvelopeProperty'." -Category InvalidData -CorrelationId $CorrelationId -Field $EnvelopeProperty)
    }

    $extracted = if ($Body -is [System.Collections.IDictionary]) { $Body[$EnvelopeProperty] } else { $Body.$EnvelopeProperty }

    if ($null -eq $extracted) {
        return $null
    }

    if ($extracted -is [System.Collections.IEnumerable] -and $extracted -isnot [string] -and $extracted -isnot [System.Collections.IDictionary]) {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $extracted) {
            $results.Add((ConvertTo-FsuTypedRecord -Item $item -PSTypeName $PSTypeName))
        }
        return $results.ToArray()
    }

    return (ConvertTo-FsuTypedRecord -Item $extracted -PSTypeName $PSTypeName)
}

function ConvertTo-FsuTypedRecord {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory helper; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Item,

        [Parameter(Mandatory)]
        [string]$PSTypeName
    )

    if ($null -eq $Item) {
        return $null
    }

    if ($Item -is [System.Collections.IDictionary]) {
        $result = [PSCustomObject]$Item
    } else {
        $result = $Item
    }

    if ($result -is [PSCustomObject]) {
        $result.PSObject.TypeNames.Insert(0, $PSTypeName)
    }

    return $result
}
