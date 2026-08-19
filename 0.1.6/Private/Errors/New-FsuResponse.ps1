function New-FsuResponse {
    <#
    .SYNOPSIS
        Constructs the 'Freshservice.Response' metadata envelope for a
        completed request (ARCHITECTURE.md §11).

    .DESCRIPTION
        Pure shape constructor only. This does not perform HTTP transport and
        does not deserialize response bodies; it packages already-extracted
        status, rate-limit metadata, correlation ID, and body into one typed
        object. Never accepts or stores authorization header values.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory object constructor; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(100, 599)]
        [int]$StatusCode,

        [Parameter(Mandatory)]
        [string]$CorrelationId,

        [AllowNull()]
        $Body,

        [Nullable[int]]$RateLimitTotal,

        [Nullable[int]]$RateLimitRemaining,

        [Nullable[int]]$RateLimitUsedCurrentRequest,

        [string]$RetryAfter,

        [string]$ApiVersion,

        # Phase 4's Invoke-FsuPagedRequest follows the `link` response header
        # (§11 "Pagination and embedding"). Carrying it on the envelope now
        # keeps ConvertFrom-FsuResponse the single place a response is
        # extracted; without it, paging would have to reach past this contract
        # to raw headers. Null for non-paged responses.
        [string]$Link
    )

    $rateLimit = [PSCustomObject]@{
        PSTypeName = 'Freshservice.Response.RateLimit'
        Total = $RateLimitTotal
        Remaining = $RateLimitRemaining
        UsedCurrentRequest = $RateLimitUsedCurrentRequest
        RetryAfter = $RetryAfter
    }

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.Response'
        StatusCode = $StatusCode
        CorrelationId = $CorrelationId
        ApiVersion = $ApiVersion
        Link = $Link
        RateLimit = $rateLimit
        Body = $Body
    }
}
