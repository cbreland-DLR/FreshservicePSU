function Test-FsuAssetFilterQuery {
    <#
    .SYNOPSIS
        Validates a Freshservice asset filter query before it is sent.

    .DESCRIPTION
        The vendor requires a quoted filter of at most 512 characters with
        at least one field condition. Empty or tautological queries are
        rejected as unbounded. workspace_id is rejected because this tenant
        has one workspace. Returns the unquoted query text for wrapping.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Query,

        [string]$CorrelationId
    )

    function Get-FsuAssetFilterErrorRecord {
        param(
            [Parameter(Mandatory)][string]$Id,
            [Parameter(Mandatory)][string]$Message,
            [string]$CorrelationId
        )
        New-FsuErrorRecord -ErrorId "FreshservicePSU.Asset.$Id" -Message $Message -Category InvalidArgument -CorrelationId $CorrelationId
    }

    if ([string]::IsNullOrWhiteSpace($Query)) {
        throw (Get-FsuAssetFilterErrorRecord -Id 'FilterEmpty' -Message 'An asset filter query is required.' -CorrelationId $CorrelationId)
    }

    $text = $Query.Trim()
    if ($text.Length -ge 2 -and $text.StartsWith('"') -and $text.EndsWith('"')) {
        $text = $text.Substring(1, $text.Length - 2).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        throw (Get-FsuAssetFilterErrorRecord -Id 'FilterEmpty' -Message 'An asset filter query is required.' -CorrelationId $CorrelationId)
    }

    if ($text.Length -gt 512) {
        throw (Get-FsuAssetFilterErrorRecord -Id 'FilterTooLong' -Message 'An asset filter query cannot exceed 512 characters.' -CorrelationId $CorrelationId)
    }

    if ($text.Contains([char]34)) {
        throw (Get-FsuAssetFilterErrorRecord -Id 'FilterMalformed' -Message 'An asset filter query cannot contain double quotes; string values use single quotes.' -CorrelationId $CorrelationId)
    }

    if ($text -match '(?i)\bworkspace_id\b') {
        throw (Get-FsuAssetFilterErrorRecord -Id 'FilterWorkspaceNotAllowed' -Message 'workspace_id is not a valid asset filter field in this module.' -CorrelationId $CorrelationId)
    }

    $depth = 0
    $inSingleQuote = $false
    foreach ($character in $text.ToCharArray()) {
        if ($character -eq [char]39) {
            $inSingleQuote = -not $inSingleQuote
            continue
        }
        if ($inSingleQuote) {
            continue
        }
        if ($character -eq [char]40) {
            $depth++
        } elseif ($character -eq [char]41) {
            $depth--
            if ($depth -lt 0) {
                throw (Get-FsuAssetFilterErrorRecord -Id 'FilterMalformed' -Message 'The asset filter query has unbalanced parentheses.' -CorrelationId $CorrelationId)
            }
        }
    }
    if ($inSingleQuote -or $depth -ne 0) {
        throw (Get-FsuAssetFilterErrorRecord -Id 'FilterMalformed' -Message 'The asset filter query has unbalanced quotes or parentheses.' -CorrelationId $CorrelationId)
    }

    if ($text -notmatch "(?i)[A-Za-z_][A-Za-z0-9_]*\s*(:>|:<|:)\s*(?:\d+|null|true|false|'[^']*')") {
        throw (Get-FsuAssetFilterErrorRecord -Id 'FilterUnbounded' -Message 'The asset filter query must contain at least one field condition.' -CorrelationId $CorrelationId)
    }

    return $text
}
