function New-FsuRetryPolicy {
    <#
    .SYNOPSIS
        Builds a 'Freshservice.RetryPolicy' configuration object
        (ARCHITECTURE.md §11 "Retry policy").

    .DESCRIPTION
        Retry budgets and bounds are configuration, never public command
        parameters. This function only builds the policy object; it performs
        no sleeping, no HTTP calls, and no clock or randomness access.

        Rate limiting is reactive (ARCHITECTURE.md §11), so the budget is
        what decides whether a 429 can actually be waited out. Freshservice
        windows are minute-level, so Retry-After can approach 60 seconds.
        Noninteractive callers get 180 seconds, enough for a full window
        wait plus the retried request. Interactive callers stay at 20
        seconds deliberately: a PSU page must not hang for a minute, so an
        interactive 429 surfaces as an error the page can render instead.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory object constructor; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateSet('Interactive', 'Noninteractive')]
        [string]$Mode = 'Interactive',

        [ValidateRange(1, 3600)]
        [double]$TotalBudgetSeconds,

        [ValidateRange(1, 20)]
        [int]$MaxAttempts = 5,

        [ValidateRange(0.0, 300.0)]
        [double]$MaxDelaySeconds = 30.0,

        [ValidateRange(0.0, 60.0)]
        [double]$BaseDelaySeconds = 0.5,

        [ValidateRange(0.0, 60.0)]
        [double]$EstimatedRequestDurationSeconds = 1.0,

        [bool]$AllowNonIdempotentReplay = $false
    )

    if (-not $PSBoundParameters.ContainsKey('TotalBudgetSeconds')) {
        $TotalBudgetSeconds = if ($Mode -eq 'Interactive') { 20.0 } else { 180.0 }
    }

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.RetryPolicy'
        Mode = $Mode
        TotalBudgetSeconds = [double]$TotalBudgetSeconds
        MaxAttempts = $MaxAttempts
        MaxDelaySeconds = $MaxDelaySeconds
        BaseDelaySeconds = $BaseDelaySeconds
        EstimatedRequestDurationSeconds = $EstimatedRequestDurationSeconds
        AllowNonIdempotentReplay = $AllowNonIdempotentReplay
    }
}
