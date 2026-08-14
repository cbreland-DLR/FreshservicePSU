function Confirm-FsuRateLimitReservation {
    <#
    .SYNOPSIS
        Reconciles a prior reservation to its actual request cost
        (ARCHITECTURE.md §11 "Rate limits").

    .DESCRIPTION
        Freshservice reports the real cost of a request in
        X-RateLimit-Used-CurrentRequest, which can differ from the
        estimated -Cost passed to Request-FsuRateLimitReservation (embedding
        adds +1/+2 credits per resource). This adjusts the bucket by the
        delta between the reserved estimate and the actual cost so the
        window's Reserved total stays accurate rather than permanently
        over- or under-counting. A reservation for an expired window is a
        no-op: the bucket has already reset and nothing needs reconciling.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'In-memory reservation bookkeeping only; no external system state is changed.')]
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Provider,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ReservationId,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$ActualCost,

        [Parameter(Mandatory)]
        [datetime]$Now,

        [string]$CorrelationId
    )

    if (-not $Provider['Available']) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Execution.RateLimiterUnavailable' -Message 'Rate-limiter provider is unavailable; cannot reconcile the reservation.' -Category ResourceUnavailable -CorrelationId $CorrelationId)
    }

    $store = $Provider['Store']

    [System.Threading.Monitor]::Enter($store)
    try {
        $bucket = $store[$Key]
        if (-not $bucket -or $bucket.ExpiresAtUtc -le $Now.ToUniversalTime()) {
            return
        }
        if (-not $bucket.Reservations.ContainsKey($ReservationId)) {
            return
        }

        $priorCost = [int]$bucket.Reservations[$ReservationId]
        $delta = $ActualCost - $priorCost
        $bucket.Reserved = [math]::Max(0, [int]$bucket.Reserved + $delta)
        $bucket.Reservations[$ReservationId] = $ActualCost
    } finally {
        [System.Threading.Monitor]::Exit($store)
    }
}
