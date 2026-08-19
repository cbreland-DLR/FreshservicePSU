function ConvertTo-FsuRequestBody {
    <#
    .SYNOPSIS
        Serializes a request body to JSON per ARCHITECTURE.md §11
        "Serialization conventions".

    .DESCRIPTION
        The only place a request body is serialized in the pipeline. Uses
        ConvertTo-Json -Depth 10, encodes as UTF-8 without a byte-order mark,
        converts DateTime values to UTC (never relabeling a Local value) and
        formats them as 'yyyy-MM-ddTHH:mm:ssZ', and distinguishes an unbound
        parameter (omitted) from one explicitly set to $null (sent as JSON
        null) via the caller-supplied BoundParameterNames list rather than
        '-eq $null' on the value. A SecureString anywhere in the input throws
        rather than serializing. Multipart bodies are out of scope (attachments
        are out of scope per CLAUDE.md); only the JSON branch is implemented.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory serialization; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Fields,

        # Names of $Fields keys that were explicitly bound by the calling
        # command's $PSBoundParameters. A key present in $Fields but absent
        # here is dropped from the body (unbound); a key present in both with
        # a $null value is emitted as JSON null (explicit null).
        [string[]]$BoundParameterNames = @(),

        [string]$CorrelationId
    )

    function Test-FsuContainsSecureString {
        param($Value)

        if ($null -eq $Value) {
            return $false
        }
        if ($Value -is [System.Security.SecureString]) {
            return $true
        }
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($k in $Value.Keys) {
                if (Test-FsuContainsSecureString -Value $Value[$k]) {
                    return $true
                }
            }
            return $false
        }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            foreach ($item in $Value) {
                if (Test-FsuContainsSecureString -Value $item) {
                    return $true
                }
            }
            return $false
        }
        return $false
    }

    function ConvertTo-FsuNormalizedValue {
        param($Value)

        if ($null -eq $Value) {
            return $null
        }
        if ($Value -is [datetime]) {
            $utc = switch ($Value.Kind) {
                'Utc' { $Value }
                'Local' { $Value.ToUniversalTime() }
                default { [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc) }
            }
            return $utc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        if ($Value -is [System.Collections.IDictionary]) {
            $out = [ordered]@{}
            foreach ($k in $Value.Keys) {
                $out[$k] = ConvertTo-FsuNormalizedValue -Value $Value[$k]
            }
            return $out
        }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            $list = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Value) {
                $list.Add((ConvertTo-FsuNormalizedValue -Value $item))
            }
            return $list.ToArray()
        }
        return $Value
    }

    if (Test-FsuContainsSecureString -Value $Fields) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Serialization.SecureStringNotAllowed' -Message 'A SecureString value cannot be serialized into a request body.' -Category InvalidArgument -CorrelationId $CorrelationId)
    }

    $ordered = [ordered]@{}
    foreach ($key in $Fields.Keys) {
        if ($key -notin $BoundParameterNames) {
            # Unbound: omitted entirely.
            continue
        }
        $ordered[$key] = ConvertTo-FsuNormalizedValue -Value $Fields[$key]
    }

    $json = $ordered | ConvertTo-Json -Depth 10 -Compress
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    return $utf8NoBom.GetBytes($json)
}
