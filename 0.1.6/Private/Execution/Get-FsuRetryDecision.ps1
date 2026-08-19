function Get-FsuRetryDecision {
    <#
    .SYNOPSIS
        Pure retry decision function for the request pipeline
        (ARCHITECTURE.md §11 "Retry policy").

    .DESCRIPTION
        Takes current attempt state and returns a decision object; it never
        sleeps, never calls Get-Random or Get-Date directly, and never
        manufactures a synthetic success. Jitter and "now" are injected by the
        caller so tests are deterministic.

        The central rule: a retry is attempted only when the computed delay
        plus the policy's estimated request duration fits inside the
        remaining budget. Otherwise the decision fails closed (ShouldRetry =
        $false) rather than sleeping into a budget it cannot afford.

        A confirmed 429 (-IsRateLimited) is treated separately from an
        ambiguous network failure (-IsNetworkFailure); both are retryable
        subject to the same budget and idempotency rules. Server-supplied
        Retry-After (seconds or HTTP-date) is honored over computed backoff.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Policy,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Attempt,

        [Parameter(Mandatory)]
        [ValidateRange(0.0, [double]::MaxValue)]
        [double]$ElapsedSeconds,

        [Nullable[int]]$StatusCode,

        [switch]$IsRateLimited,

        [switch]$IsNetworkFailure,

        [Nullable[double]]$RetryAfterSeconds,

        [string]$RetryAfterHttpDate,

        [Parameter(Mandatory)]
        [datetime]$Now,

        [bool]$IsIdempotent = $true,

        [ValidateRange(0.0, 1.0)]
        [double]$JitterFraction = 0.5
    )

    if ($Policy.PSObject.TypeNames -notcontains 'Freshservice.RetryPolicy') {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Execution.InvalidRetryPolicy' -Message 'Policy must be a Freshservice.RetryPolicy object.' -Category InvalidArgument)
    }

    $retryableStatuses = @(408, 500, 502, 503, 504)
    $isRetryableSignal = $IsRateLimited.IsPresent -or $IsNetworkFailure.IsPresent -or ($null -ne $StatusCode -and $StatusCode -in $retryableStatuses)

    function ConvertTo-FsuRetryDecisionResult {
        param(
            [Parameter(Mandatory)]
            [bool]$ShouldRetry,

            [Parameter(Mandatory)]
            [string]$Reason,

            [double]$DelaySeconds = 0.0
        )

        return [PSCustomObject]@{
            PSTypeName = 'Freshservice.RetryDecision'
            ShouldRetry = $ShouldRetry
            DelaySeconds = $DelaySeconds
            Reason = $Reason
        }
    }

    if (-not $isRetryableSignal) {
        return ConvertTo-FsuRetryDecisionResult -ShouldRetry $false -Reason 'NotRetryable'
    }

    if ($Attempt -ge $Policy.MaxAttempts) {
        return ConvertTo-FsuRetryDecisionResult -ShouldRetry $false -Reason 'MaxAttemptsReached'
    }

    if (-not $IsIdempotent -and -not $Policy.AllowNonIdempotentReplay) {
        return ConvertTo-FsuRetryDecisionResult -ShouldRetry $false -Reason 'NonIdempotentReplayNotAllowed'
    }

    $delaySeconds = 0.0
    if ($null -ne $RetryAfterSeconds) {
        $delaySeconds = [math]::Max(0.0, $RetryAfterSeconds)
    } elseif ($RetryAfterHttpDate) {
        $parsedDate = [System.DateTimeOffset]::MinValue
        if (-not [System.DateTimeOffset]::TryParse($RetryAfterHttpDate, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsedDate)) {
            return ConvertTo-FsuRetryDecisionResult -ShouldRetry $false -Reason 'InvalidRetryAfterHttpDate'
        }
        # Convert a Local $Now to UTC rather than relabeling it. SpecifyKind
        # would stamp a local wall-clock reading as UTC, so on a UTC-7 host a
        # Retry-After five seconds out reads as ~6 hours out and the retry is
        # wrongly refused as budget-exhausting. Only a genuinely Unspecified
        # kind is assumed to already be UTC.
        $nowUtc = if ($Now.Kind -eq [System.DateTimeKind]::Unspecified) {
            [datetime]::SpecifyKind($Now, [System.DateTimeKind]::Utc)
        } else {
            $Now.ToUniversalTime()
        }
        $nowOffset = [System.DateTimeOffset]::new($nowUtc)
        $delaySeconds = [math]::Max(0.0, ($parsedDate - $nowOffset).TotalSeconds)
    } else {
        $backoff = [math]::Min($Policy.MaxDelaySeconds, $Policy.BaseDelaySeconds * [math]::Pow(2, $Attempt - 1))
        $delaySeconds = [math]::Min($Policy.MaxDelaySeconds, $backoff * (0.5 + (0.5 * $JitterFraction)))
    }

    $remainingBudget = $Policy.TotalBudgetSeconds - $ElapsedSeconds
    $requiredCapacity = $delaySeconds + $Policy.EstimatedRequestDurationSeconds

    if ($remainingBudget -le 0 -or $requiredCapacity -gt $remainingBudget) {
        return ConvertTo-FsuRetryDecisionResult -ShouldRetry $false -Reason 'BudgetExhausted' -DelaySeconds $delaySeconds
    }

    return ConvertTo-FsuRetryDecisionResult -ShouldRetry $true -Reason 'Retry' -DelaySeconds $delaySeconds
}
