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

    if ($Provider.PSObject.TypeNames -notcontains 'Freshservice.RateLimiter.InMemoryProvider') {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Execution.InvalidRateLimiterProvider' -Message 'Provider must be a Freshservice.RateLimiter.InMemoryProvider object.' -Category InvalidArgument -CorrelationId $CorrelationId)
    }

    if (-not $Provider.Available) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Execution.RateLimiterUnavailable' -Message 'Rate-limiter provider is unavailable; failing closed rather than sending the request unlimited.' -Category ResourceUnavailable -CorrelationId $CorrelationId)
    }

    $store = $Provider.Store
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
