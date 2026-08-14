function Request-FsuRateLimitReservation {
    <#
    .SYNOPSIS
        Atomically reserves rate-limiter capacity before a request is sent
        (ARCHITECTURE.md §11 "Rate limits").

    .DESCRIPTION
        Fails closed: if -Provider.Available is $false, throws a normalized
        terminating error rather than allowing the caller to proceed as if
        unlimited. Never falls back to a different, uncoordinated limiter.
        A stale window (older than the key's window) resets the bucket
        before evaluating capacity, so expiry is handled deterministically
        from the injected -Now rather than a background sweep. The decision
        never calls Get-Date or Get-Random.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'In-memory reservation bookkeeping only; no external system state is changed.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Provider,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Limit,

        [Parameter(Mandatory)]
        [datetime]$Now,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Cost = 1,

        [ValidateRange(1, 3600)]
        [int]$WindowSeconds = 60,

        [string]$CorrelationId
    )

    # Index access only, never PSObject.TypeNames or .Properties. One provider
    # instance is shared by every runspace that reserves capacity — that is the
    # point of the limiter — and concurrent member access through the PSObject
    # adapter is not thread-safe: it intermittently throws, which would reject
    # a legitimate reservation under exactly the contention this limiter exists
    # to arbitrate. So this stays correct when many
    # runspaces validate the same shared provider at once. Checking shape
    # rather than a type name also keeps this open to the production provider,
    # which is a different ProviderKind.
    if ($Provider -isnot [System.Collections.IDictionary] -or
        [string]::IsNullOrWhiteSpace([string]$Provider['ProviderKind']) -or
        $null -eq $Provider['Store']) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Execution.InvalidRateLimiterProvider' -Message 'Provider must be a rate-limiter provider exposing ProviderKind, Available, and Store.' -Category InvalidArgument -CorrelationId $CorrelationId)
    }

    if (-not $Provider['Available']) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Execution.RateLimiterUnavailable' -Message 'Rate-limiter provider is unavailable; failing closed rather than sending the request unlimited.' -Category ResourceUnavailable -CorrelationId $CorrelationId)
    }

    $store = $Provider['Store']
    $reservationId = [guid]::NewGuid().ToString()

    [System.Threading.Monitor]::Enter($store)
    try {
        $windowExpiresAt = $Now.ToUniversalTime().AddSeconds($WindowSeconds)

        $bucket = $store[$Key]
        if (-not $bucket -or $bucket.ExpiresAtUtc -le $Now.ToUniversalTime()) {
            $bucket = @{
                Reserved = 0
                ExpiresAtUtc = $windowExpiresAt
                Reservations = @{}
            }
            $store[$Key] = $bucket
        }

        $remaining = $Limit - [int]$bucket.Reserved
        if ($Cost -gt $remaining) {
            $retryAfter = [math]::Max(0.0, ($bucket.ExpiresAtUtc - $Now.ToUniversalTime()).TotalSeconds)
            return [PSCustomObject]@{
                PSTypeName = 'Freshservice.RateLimiter.Decision'
                Allowed = $false
                ReservationId = $null
                Key = $Key
                Remaining = $remaining
                RetryAfterSeconds = $retryAfter
            }
        }

        $bucket.Reserved = [int]$bucket.Reserved + $Cost
        $bucket.Reservations[$reservationId] = $Cost

        return [PSCustomObject]@{
            PSTypeName = 'Freshservice.RateLimiter.Decision'
            Allowed = $true
            ReservationId = $reservationId
            Key = $Key
            Remaining = $Limit - [int]$bucket.Reserved
            RetryAfterSeconds = 0.0
        }
    } finally {
        [System.Threading.Monitor]::Exit($store)
    }
}
