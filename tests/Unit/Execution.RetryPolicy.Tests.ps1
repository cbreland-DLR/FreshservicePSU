<#
.SYNOPSIS
    Unit tests for New-FsuRetryPolicy and Get-FsuRetryDecision
    (ARCHITECTURE.md §11 "Retry policy").
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Execution/Get-FsuRetryDecision.ps1')

    $script:fixedNow = [datetime]::new(2026, 8, 13, 12, 0, 0, [System.DateTimeKind]::Utc)
}

Describe 'New-FsuRetryPolicy: budgets are configuration, not parameters' {

    It 'defaults the interactive budget to 20 seconds' {
        (New-FsuRetryPolicy -Mode Interactive).TotalBudgetSeconds | Should -Be 20.0
    }

    It 'defaults the noninteractive budget to 120 seconds' {
        (New-FsuRetryPolicy -Mode Noninteractive).TotalBudgetSeconds | Should -Be 120.0
    }

    It 'produces a Freshservice.RetryPolicy typed object' {
        (New-FsuRetryPolicy).PSObject.TypeNames | Should -Contain 'Freshservice.RetryPolicy'
    }
}

Describe 'Get-FsuRetryDecision: the central budget rule' {

    BeforeAll {
        # BaseDelaySeconds 1, MaxDelaySeconds 8, EstimatedRequestDurationSeconds 1
        # -> attempt 1 backoff with JitterFraction 1.0 is min(8, 1*2^0)*(0.5+0.5) = 1.0s
        $script:policy = New-FsuRetryPolicy -TotalBudgetSeconds 20 -MaxAttempts 5 -BaseDelaySeconds 1.0 -MaxDelaySeconds 8.0 -EstimatedRequestDurationSeconds 1.0
    }

    It 'retries when the computed delay plus estimated request duration fits inside the remaining budget' {
        # remaining = 20 - 10 = 10; required = 1.0(delay) + 1.0(duration) = 2.0 <= 10
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 10.0 -StatusCode 500 -Now $fixedNow -JitterFraction 1.0
        $decision.ShouldRetry | Should -Be $true
        $decision.Reason | Should -Be 'Retry'
    }

    It 'fails immediately (does not retry) when the wait would not fit inside the remaining budget' {
        # remaining = 20 - 19.5 = 0.5; required = 1.0(delay) + 1.0(duration) = 2.0 > 0.5
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 19.5 -StatusCode 500 -Now $fixedNow -JitterFraction 1.0
        $decision.ShouldRetry | Should -Be $false
        $decision.Reason | Should -Be 'BudgetExhausted'
    }

    It 'is a pure function: two calls with identical inputs return identical decisions' {
        $first = Get-FsuRetryDecision -Policy $policy -Attempt 2 -ElapsedSeconds 3.0 -StatusCode 503 -Now $fixedNow -JitterFraction 0.25
        $second = Get-FsuRetryDecision -Policy $policy -Attempt 2 -ElapsedSeconds 3.0 -StatusCode 503 -Now $fixedNow -JitterFraction 0.25
        $first.ShouldRetry | Should -Be $second.ShouldRetry
        $first.DelaySeconds | Should -Be $second.DelaySeconds
    }
}

Describe 'Get-FsuRetryDecision: Retry-After in seconds form' {

    BeforeAll {
        $script:policy = New-FsuRetryPolicy -TotalBudgetSeconds 20 -MaxAttempts 5 -EstimatedRequestDurationSeconds 1.0
    }

    It 'honors an explicit Retry-After seconds value over computed backoff' {
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -IsRateLimited -RetryAfterSeconds 3.0 -Now $fixedNow
        $decision.DelaySeconds | Should -Be 3.0
        $decision.ShouldRetry | Should -Be $true
    }

    # A Retry-After longer than the whole budget must decline the retry, NOT
    # clamp the server's instruction down to MaxDelaySeconds and retry early.
    # Retrying sooner than the server asked is the worse failure: it ignores a
    # documented 429 instruction and invites another. The budget rule already
    # produces the right answer here, and this test is what keeps a later
    # "cap the individual delay" change from silently turning it into an
    # early retry.
    It 'declines rather than clamping when Retry-After exceeds the total budget' {
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -IsRateLimited -RetryAfterSeconds 86400 -Now $fixedNow
        $decision.ShouldRetry | Should -Be $false
        $decision.Reason | Should -Be 'BudgetExhausted'
    }
}

Describe 'Get-FsuRetryDecision: Retry-After in HTTP-date form' {

    BeforeAll {
        $script:policy = New-FsuRetryPolicy -TotalBudgetSeconds 20 -MaxAttempts 5 -EstimatedRequestDurationSeconds 1.0
    }

    It 'honors an HTTP-date Retry-After by computing the delay against the injected clock' {
        $httpDate = $fixedNow.AddSeconds(5).ToString('R')
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -IsRateLimited -RetryAfterHttpDate $httpDate -Now $fixedNow
        $decision.DelaySeconds | Should -BeGreaterOrEqual 4.9
        $decision.DelaySeconds | Should -BeLessOrEqual 5.1
    }

    # Relabeling a Local $Now as UTC instead of converting it turns a 5-second
    # Retry-After into hours on any host that is not on UTC, and the retry is
    # then wrongly refused as budget-exhausting.
    It 'computes the same delay whether the injected clock is Local or UTC' {
        $localNow = [datetime]::new(2026, 8, 13, 12, 0, 0, [System.DateTimeKind]::Local)
        $httpDate = $localNow.ToUniversalTime().AddSeconds(5).ToString('R')
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -IsRateLimited -RetryAfterHttpDate $httpDate -Now $localNow

        $decision.ShouldRetry | Should -Be $true
        $decision.DelaySeconds | Should -BeGreaterOrEqual 4.9
        $decision.DelaySeconds | Should -BeLessOrEqual 5.1
    }

    It 'clamps a past HTTP-date to zero delay rather than a negative wait' {
        $httpDate = $fixedNow.AddSeconds(-30).ToString('R')
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -IsRateLimited -RetryAfterHttpDate $httpDate -Now $fixedNow
        $decision.DelaySeconds | Should -Be 0.0
    }
}

Describe 'Get-FsuRetryDecision: jitter bounds with an injected generator' {

    BeforeAll {
        $script:policy = New-FsuRetryPolicy -TotalBudgetSeconds 60 -MaxAttempts 5 -BaseDelaySeconds 2.0 -MaxDelaySeconds 10.0 -EstimatedRequestDurationSeconds 0.1
    }

    It 'stays within [0.5, 1.0] of the uncapped backoff across the injected jitter range' {
        # attempt 1 uncapped backoff = BaseDelaySeconds * 2^0 = 2.0
        $lowJitter = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -StatusCode 500 -Now $fixedNow -JitterFraction 0.0
        $highJitter = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -StatusCode 500 -Now $fixedNow -JitterFraction 1.0

        $lowJitter.DelaySeconds | Should -Be 1.0
        $highJitter.DelaySeconds | Should -Be 2.0
        $lowJitter.DelaySeconds | Should -BeLessOrEqual $highJitter.DelaySeconds
    }

    It 'never reaches Get-Random directly (delay is fully determined by the injected JitterFraction)' {
        $first = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -StatusCode 500 -Now $fixedNow -JitterFraction 0.5
        $second = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -StatusCode 500 -Now $fixedNow -JitterFraction 0.5
        $first.DelaySeconds | Should -Be $second.DelaySeconds
    }
}

Describe 'Get-FsuRetryDecision: idempotent vs non-idempotent' {

    BeforeAll {
        $script:policy = New-FsuRetryPolicy -TotalBudgetSeconds 20 -MaxAttempts 5 -EstimatedRequestDurationSeconds 1.0
    }

    It 'retries an idempotent operation by default' {
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -StatusCode 500 -Now $fixedNow -IsIdempotent $true -JitterFraction 0.5
        $decision.ShouldRetry | Should -Be $true
    }

    It 'refuses to replay a non-idempotent operation when the policy does not allow it' {
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -StatusCode 500 -Now $fixedNow -IsIdempotent $false -JitterFraction 0.5
        $decision.ShouldRetry | Should -Be $false
        $decision.Reason | Should -Be 'NonIdempotentReplayNotAllowed'
    }

    It 'replays a non-idempotent operation only when explicitly approved by policy' {
        $approvingPolicy = New-FsuRetryPolicy -TotalBudgetSeconds 20 -MaxAttempts 5 -EstimatedRequestDurationSeconds 1.0 -AllowNonIdempotentReplay $true
        $decision = Get-FsuRetryDecision -Policy $approvingPolicy -Attempt 1 -ElapsedSeconds 0 -StatusCode 500 -Now $fixedNow -IsIdempotent $false -JitterFraction 0.5
        $decision.ShouldRetry | Should -Be $true
    }
}

Describe 'Get-FsuRetryDecision: confirmed 429 vs ambiguous network failure' {

    BeforeAll {
        $script:policy = New-FsuRetryPolicy -TotalBudgetSeconds 20 -MaxAttempts 5 -EstimatedRequestDurationSeconds 1.0
    }

    It 'retries a confirmed 429 signaled via -IsRateLimited' {
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -StatusCode 429 -IsRateLimited -Now $fixedNow -JitterFraction 0.5
        $decision.ShouldRetry | Should -Be $true
    }

    It 'retries an ambiguous network failure signaled via -IsNetworkFailure with no status code' {
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -IsNetworkFailure -Now $fixedNow -JitterFraction 0.5
        $decision.ShouldRetry | Should -Be $true
    }

    It 'does not retry a non-retryable status with neither signal present' {
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 1 -ElapsedSeconds 0 -StatusCode 400 -Now $fixedNow -JitterFraction 0.5
        $decision.ShouldRetry | Should -Be $false
        $decision.Reason | Should -Be 'NotRetryable'
    }
}

Describe 'Get-FsuRetryDecision: attempt cap' {

    BeforeAll {
        $script:policy = New-FsuRetryPolicy -TotalBudgetSeconds 120 -MaxAttempts 3 -EstimatedRequestDurationSeconds 0.1
    }

    It 'stops retrying once MaxAttempts is reached even with ample remaining budget' {
        $decision = Get-FsuRetryDecision -Policy $policy -Attempt 3 -ElapsedSeconds 1.0 -StatusCode 500 -Now $fixedNow -JitterFraction 0.5
        $decision.ShouldRetry | Should -Be $false
        $decision.Reason | Should -Be 'MaxAttemptsReached'
    }
}

Describe 'Get-FsuRetryDecision: never manufactures a synthetic success' {

    It 'the decision object never carries a Body, StatusCode, or success indicator field' {
        $decision = Get-FsuRetryDecision -Policy (New-FsuRetryPolicy) -Attempt 1 -ElapsedSeconds 0 -StatusCode 500 -Now $fixedNow -JitterFraction 0.5
        $decision.PSObject.Properties.Name | Should -Not -Contain 'Body'
        $decision.PSObject.Properties.Name | Should -Not -Contain 'Success'
    }
}
