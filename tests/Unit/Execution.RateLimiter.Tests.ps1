<#
.SYNOPSIS
    Unit tests for the rate-limiter provider contract and in-memory
    provider (ARCHITECTURE.md §11 "Rate limits").
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Execution/New-FsuRateLimiterKey.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Execution/New-FsuInMemoryRateLimiterProvider.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Execution/Request-FsuRateLimitReservation.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Execution/Confirm-FsuRateLimitReservation.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Execution/Clear-FsuRateLimitReservation.ps1')

    $script:now = [datetime]::new(2026, 8, 13, 12, 0, 0, [System.DateTimeKind]::Utc)
}

Describe 'New-FsuRateLimiterKey key isolation' {
    It 'differs by stage' {
        $a = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $b = New-FsuRateLimiterKey -Stage 'dev' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $a | Should -Not -Be $b
    }
    It 'differs by tenant' {
        $a = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $b = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't2' -EndpointClass 'ListTicket' -Now $now
        $a | Should -Not -Be $b
    }
    It 'differs by endpoint class' {
        $a = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $b = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ViewTicket' -Now $now
        $a | Should -Not -Be $b
    }
    It 'differs by minute window' {
        $a = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $b = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now.AddMinutes(1)
        $a | Should -Not -Be $b
    }
    It 'is deterministic for the same inputs (no direct clock access)' {
        $a = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $b = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $a | Should -Be $b
    }
}

Describe 'Reserve / reconcile / release lifecycle' {

    BeforeEach {
        $script:provider = New-FsuInMemoryRateLimiterProvider
        $script:key = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
    }

    It 'reserves capacity and allows the request' {
        $decision = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 140 -Now $now
        $decision.Allowed | Should -Be $true
        $decision.Remaining | Should -Be 139
        $decision.ReservationId | Should -Not -BeNullOrEmpty
    }

    It 'rejects a reservation that would exceed the limit' {
        1..5 | ForEach-Object { Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 5 -Now $now | Out-Null }
        $decision = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 5 -Now $now
        $decision.Allowed | Should -Be $false
        $decision.Remaining | Should -Be 0
    }

    It 'reconciles a reservation down to a lower actual cost, freeing capacity' {
        $decision = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 5 -Now $now -Cost 2
        Confirm-FsuRateLimitReservation -Provider $provider -Key $key -ReservationId $decision.ReservationId -ActualCost 1 -Now $now
        $next = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 5 -Now $now -Cost 4
        $next.Allowed | Should -Be $true
    }

    It 'reconciles a reservation up to a higher actual cost, consuming more capacity' {
        $decision = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 5 -Now $now -Cost 1
        Confirm-FsuRateLimitReservation -Provider $provider -Key $key -ReservationId $decision.ReservationId -ActualCost 3 -Now $now
        $next = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 5 -Now $now -Cost 3
        $next.Allowed | Should -Be $false
    }

    It 'releases a reservation and returns its capacity to the window' {
        $decision = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 1 -Now $now
        Clear-FsuRateLimitReservation -Provider $provider -Key $key -ReservationId $decision.ReservationId -Now $now
        $next = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 1 -Now $now
        $next.Allowed | Should -Be $true
    }
}

Describe 'Contention between two reservations' {
    It 'a second reservation sees the first''s consumed capacity atomically' {
        $provider = New-FsuInMemoryRateLimiterProvider
        $key = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $first = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 2 -Now $now
        $second = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 2 -Now $now
        $third = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 2 -Now $now
        $first.Allowed | Should -Be $true
        $second.Allowed | Should -Be $true
        $third.Allowed | Should -Be $false
    }

    It 'rejects an object that is not a rate-limiter provider' {
        $errorId = $null
        try {
            Request-FsuRateLimitReservation -Provider ([pscustomobject]@{ Nope = 1 }) -Key 'k' -Limit 10 -Now $now | Out-Null
        } catch {
            $errorId = $_.FullyQualifiedErrorId
        }
        $errorId | Should -Match 'FreshservicePSU\.Execution\.InvalidRateLimiterProvider'
    }

    It 'concurrent threads reserving against the same key never both succeed past the limit' {
        $provider = New-FsuInMemoryRateLimiterProvider
        $key = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $scriptBlock = {
            param($ProviderRef, $KeyRef, $NowRef, $ModulePath)
            . $ModulePath
            Request-FsuRateLimitReservation -Provider $ProviderRef -Key $KeyRef -Limit 10 -Now $NowRef
        }
        $modulePath = Join-Path $repoRoot 'FreshservicePSU/Private/Execution/Request-FsuRateLimitReservation.ps1'
        $errorRecordPath = Join-Path $repoRoot 'FreshservicePSU/Private/Errors/New-FsuErrorRecord.ps1'
        $jobs = 1..20 | ForEach-Object {
            [PowerShell]::Create().AddScript({
                    param($ProviderRef, $KeyRef, $NowRef, $ErrPath, $ReqPath)
                    . $ErrPath
                    . $ReqPath
                    Request-FsuRateLimitReservation -Provider $ProviderRef -Key $KeyRef -Limit 10 -Now $NowRef
                }).AddArgument($provider).AddArgument($key).AddArgument($now).AddArgument($errorRecordPath).AddArgument($modulePath)
        }
        $handles = $jobs | ForEach-Object { $_.BeginInvoke() }
        $results = for ($i = 0; $i -lt $jobs.Count; $i++) { $jobs[$i].EndInvoke($handles[$i]) }
        $jobs | ForEach-Object { $_.Dispose() }

        $allowedCount = @($results | Where-Object { $_.Allowed }).Count
        $allowedCount | Should -Be 10
    }
}

Describe 'Stale-window expiry' {
    It 'a reservation window resets after the window elapses' {
        $provider = New-FsuInMemoryRateLimiterProvider
        $key1 = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        1..3 | ForEach-Object { Request-FsuRateLimitReservation -Provider $provider -Key $key1 -Limit 3 -Now $now | Out-Null }
        $exhausted = Request-FsuRateLimitReservation -Provider $provider -Key $key1 -Limit 3 -Now $now
        $exhausted.Allowed | Should -Be $false

        $later = $now.AddSeconds(61)
        $key2 = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $later
        $afterExpiry = Request-FsuRateLimitReservation -Provider $provider -Key $key2 -Limit 3 -Now $later
        $afterExpiry.Allowed | Should -Be $true
    }
}

Describe 'Fail-closed on provider unavailability' {

    It 'refuses a reservation before any request would be sent when the provider is unavailable' {
        $provider = New-FsuInMemoryRateLimiterProvider -Available:$false
        $key = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        { Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 140 -Now $now } | Should -Throw
    }

    It 'the fail-closed error carries the FreshservicePSU.Execution.RateLimiterUnavailable id' {
        $provider = New-FsuInMemoryRateLimiterProvider -Available:$false
        $key = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $errorId = $null
        try {
            Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 140 -Now $now | Out-Null
        } catch {
            $errorId = $_.FullyQualifiedErrorId
        }
        $errorId | Should -Match 'FreshservicePSU\.Execution\.RateLimiterUnavailable'
    }

    It 'never falls back to a different production limiter when unavailable (no reservation is recorded)' {
        $provider = New-FsuInMemoryRateLimiterProvider -Available:$false
        $key = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        try {
            Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 140 -Now $now | Out-Null
        } catch {
            Write-Verbose "Expected fail-closed error: $($_.FullyQualifiedErrorId)"
        }
        $provider.Store.ContainsKey($key) | Should -Be $false
    }
}

Describe 'Deterministic clock injection' {
    It 'never calls Get-Date internally; identical -Now input yields identical window expiry' {
        $provider = New-FsuInMemoryRateLimiterProvider
        $key = New-FsuRateLimiterKey -Stage 'prod' -Tenant 't1' -EndpointClass 'ListTicket' -Now $now
        $first = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 5 -Now $now
        Start-Sleep -Milliseconds 5
        $second = Request-FsuRateLimitReservation -Provider $provider -Key $key -Limit 5 -Now $now
        # Both reservations against the same injected -Now must land in the
        # same window/bucket regardless of real wall-clock time elapsed
        # between the two calls.
        $second.Remaining | Should -Be ($first.Remaining - 1)
    }
}
