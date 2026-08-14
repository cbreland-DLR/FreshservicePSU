function New-FsuRetryPolicy {
    <#
    .SYNOPSIS
        Builds a 'Freshservice.RetryPolicy' configuration object
        (ARCHITECTURE.md §11 "Retry policy").

    .DESCRIPTION
        Retry budgets and bounds are configuration, never public command
        parameters. Interactive callers default to a 20-second total-time
        budget; noninteractive callers default to 120 seconds. This function
        only builds the policy object; it performs no sleeping, no HTTP calls,
        and no clock or randomness access.
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
        $TotalBudgetSeconds = if ($Mode -eq 'Interactive') { 20.0 } else { 120.0 }
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
