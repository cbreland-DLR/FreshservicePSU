function New-FsuRateLimiterKey {
    <#
    .SYNOPSIS
        Builds a deterministic rate-limiter key (ARCHITECTURE.md §11 "Rate
        limits").

    .DESCRIPTION
        Keys include a schema version, stage, tenant, endpoint class, and
        minute window so a paginated list query's 140/min sublimit is tracked
        separately from the 500/min overall budget, and so one tenant's or
        stage's state can never be read or mutated by another's key. The
        window boundary is computed from an injected -Now rather than
        Get-Date, so key generation is deterministic under test.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory key construction; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateRange(1, 999)]
        [int]$SchemaVersion = 1,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Stage,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Tenant,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointClass,

        [Parameter(Mandatory)]
        [datetime]$Now,

        [ValidateRange(1, 3600)]
        [int]$WindowSeconds = 60
    )

    $nowUtc = switch ($Now.Kind) {
        'Utc' { $Now }
        'Local' { $Now.ToUniversalTime() }
        default { [datetime]::SpecifyKind($Now, [System.DateTimeKind]::Utc) }
    }

    $epochSeconds = [long][System.DateTimeOffset]::new($nowUtc).ToUnixTimeSeconds()
    $windowStart = $epochSeconds - ($epochSeconds % $WindowSeconds)

    return 'v{0}|{1}|{2}|{3}|{4}' -f $SchemaVersion, $Stage, $Tenant, $EndpointClass, $windowStart
}
