function New-FsuInMemoryRateLimiterProvider {
    <#
    .SYNOPSIS
        Constructs the TEST-ONLY in-memory rate-limiter provider
        (ARCHITECTURE.md §11 "Rate limits").

    .DESCRIPTION
        Implements the atomic reserve/reconcile/release/expiry provider
        contract entirely in a process-local, caller-owned store. This
        provider is explicitly test-only: the production provider (PSU
        server-level cache under an OS-named mutex, IMPLEMENTATION_PLAN.md
        §8) is out of scope here and MUST NOT be synthesized by falling back
        to this one. The returned object carries an 'Available' flag a test
        can flip to $false to exercise the fail-closed path; no request
        pipeline may treat provider unavailability as "proceed unlimited".

        The store is a .NET Hashtable created with [Hashtable]::Synchronized
        so concurrent reservations from multiple runspaces/threads in a test
        serialize correctly; Request/Confirm/Clear-FsuRateLimitReservation
        additionally take Monitor.Enter/Exit around each read-modify-write to
        make reserve-and-check atomic rather than merely giving each field
        access atomicity.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory object constructor; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [bool]$Available = $true
    )

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.RateLimiter.InMemoryProvider'
        ProviderKind = 'InMemoryTestOnly'
        Available = $Available
        Store = [hashtable]::Synchronized(@{})
    }
}
