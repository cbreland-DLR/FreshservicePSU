function New-FsuUri {
    <#
    .SYNOPSIS
        Builds a request [System.Uri] from a validated base URI, path
        segments, and query parameters (ARCHITECTURE.md §11 "Pagination and
        embedding").

    .DESCRIPTION
        Pure URI construction only; this performs no HTTP transport. Each
        path segment is escaped individually with
        [Uri]::EscapeDataString so a segment containing '/', a space,
        Unicode, or a reserved character cannot alter the path structure or
        escape the base URI's '/api/v2/' root. Query values are encoded and
        support both scalar and array shapes. `per_page` is validated 1-100
        inclusive and `page` is refused above 500, per §11.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory URI construction; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([System.Uri])]
    param(
        [Parameter(Mandatory)]
        [System.Uri]$BaseUri,

        [string[]]$PathSegments = @(),

        [System.Collections.IDictionary]$QueryParameters,

        [string]$CorrelationId
    )

    if (-not $BaseUri.IsAbsoluteUri) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.InvalidBaseUri' -Message 'BaseUri must be an absolute URI.' -Category InvalidArgument -CorrelationId $CorrelationId)
    }

    $basePath = $BaseUri.AbsolutePath.TrimEnd('/')

    $encodedSegments = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in $PathSegments) {
        if ([string]::IsNullOrEmpty($segment)) {
            continue
        }
        # Escape the WHOLE segment as one opaque data unit. A segment
        # containing '/' becomes '%2F', not a path separator, so a caller
        # cannot smuggle '../' or an extra path level past this point and
        # escape the '/api/v2/' root the base URI establishes.
        $encodedSegments.Add([System.Uri]::EscapeDataString($segment))
    }

    $fullPath = if ($encodedSegments.Count -gt 0) {
        $basePath + '/' + ($encodedSegments -join '/')
    } else {
        $basePath
    }

    $queryPairs = [System.Collections.Generic.List[string]]::new()
    if ($QueryParameters) {
        foreach ($key in $QueryParameters.Keys) {
            $value = $QueryParameters[$key]

            if ($key -eq 'per_page') {
                $perPageInt = 0
                if (-not [int]::TryParse([string]$value, [ref]$perPageInt) -or $perPageInt -lt 1 -or $perPageInt -gt 100) {
                    throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.InvalidPerPage' -Message "per_page must be between 1 and 100 inclusive; narrow the query and retry. Received: $value" -Category InvalidArgument -CorrelationId $CorrelationId)
                }
            }

            if ($key -eq 'page') {
                $pageInt = 0
                if ([int]::TryParse([string]$value, [ref]$pageInt) -and $pageInt -gt 500) {
                    throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.PageTooLarge' -Message "Page $pageInt exceeds the maximum supported page (500). Narrow the query (e.g. with a filter or date range) instead of paging further." -Category InvalidArgument -CorrelationId $CorrelationId)
                }
            }

            if ($null -eq $value) {
                continue
            }

            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                foreach ($item in $value) {
                    if ($null -eq $item) {
                        continue
                    }
                    $queryPairs.Add(('{0}={1}' -f [System.Uri]::EscapeDataString([string]$key), [System.Uri]::EscapeDataString([string]$item)))
                }
            } else {
                $queryPairs.Add(('{0}={1}' -f [System.Uri]::EscapeDataString([string]$key), [System.Uri]::EscapeDataString([string]$value)))
            }
        }
    }

    $builder = [System.UriBuilder]::new($BaseUri)
    $builder.Path = $fullPath
    $builder.Query = if ($queryPairs.Count -gt 0) { ($queryPairs -join '&') } else { '' }

    $resultUri = $builder.Uri

    # Defense in depth: after building, confirm the result's path still
    # begins with the base path. EscapeDataString on whole segments already
    # prevents this, but the check makes the invariant explicit and
    # independently verifiable.
    if (-not $resultUri.AbsolutePath.StartsWith($basePath, [System.StringComparison]::Ordinal)) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.PathEscape' -Message 'Resolved URI path escaped the base URI path.' -Category InvalidArgument -CorrelationId $CorrelationId)
    }

    return $resultUri
}
