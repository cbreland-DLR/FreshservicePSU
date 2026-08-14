function Clear-FsuRateLimitReservation {
    <#
    .SYNOPSIS
        Releases a reservation without sending its request (ARCHITECTURE.md
        §11 "Rate limits").

    .DESCRIPTION
        Used when a reserved request is abandoned before send (e.g. a
        cancellation or an earlier pipeline failure) so its capacity is
        returned to the window rather than being held until expiry. A
        release against an already-expired window or an unknown reservation
        is a no-op, matching Confirm-FsuRateLimitReservation's behavior.
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
        [datetime]$Now,

        [string]$CorrelationId
    )

    if (-not $Provider.Available) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Execution.RateLimiterUnavailable' -Message 'Rate-limiter provider is unavailable; cannot release the reservation.' -Category ResourceUnavailable -CorrelationId $CorrelationId)
    }

    $store = $Provider.Store

    [System.Threading.Monitor]::Enter($store)
    try {
        $bucket = $store[$Key]
        if (-not $bucket -or $bucket.ExpiresAtUtc -le $Now.ToUniversalTime()) {
            return
        }
        if (-not $bucket.Reservations.ContainsKey($ReservationId)) {
            return
        }

        $cost = [int]$bucket.Reservations[$ReservationId]
        $bucket.Reserved = [math]::Max(0, [int]$bucket.Reserved - $cost)
        $bucket.Reservations.Remove($ReservationId)
    } finally {
        [System.Threading.Monitor]::Exit($store)
    }
}
