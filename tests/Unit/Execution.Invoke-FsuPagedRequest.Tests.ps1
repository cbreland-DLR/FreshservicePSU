<#
.SYNOPSIS
    Unit tests for Invoke-FsuPagedRequest (ARCHITECTURE.md §11 pagination).
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Errors/New-FsuResponse.ps1')
    . (Join-Path $private 'Errors/ConvertTo-FsuNormalizedError.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuRequestBody.ps1')
    . (Join-Path $private 'Serialization/ConvertFrom-FsuResponse.ps1')
    . (Join-Path $private 'Http/New-FsuUri.ps1')
    . (Join-Path $private 'Http/ConvertTo-FsuAuthorizationHeader.ps1')
    . (Join-Path $private 'Http/Send-FsuHttpRequest.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $private 'Execution/Get-FsuRetryDecision.ps1')
    . (Join-Path $private 'Execution/New-FsuAuditEvent.ps1')
    . (Join-Path $private 'Execution/Write-FsuAuditEvent.ps1')
    . (Join-Path $private 'Execution/Invoke-FsuRequest.ps1')
    . (Join-Path $private 'Execution/Invoke-FsuPagedRequest.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:apiKey = 'test-api-key-DO-NOT-LEAK-pipe'
}

Describe 'Invoke-FsuPagedRequest' {

    It 'stops when the Link header is absent' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1},{"id":2}]}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
        )
        $rows = @(Invoke-FsuPagedRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -PathSegments @('tickets') `
                -EnvelopeProperty tickets `
                -PSTypeName 'FreshservicePSU.Ticket' `
                -PerPage 100 `
                -Transport $probe.Transport)

        $rows.Count | Should -Be 2
        $rows[0].id | Should -Be 1
        $rows[0].PSObject.TypeNames | Should -Contain 'FreshservicePSU.Ticket'
        $probe.State.Request.Count | Should -Be 1
    }

    It 'follows rel=next and streams both pages' {
        $next = 'https://acme.freshservice.com/api/v2/tickets?page=2&per_page=1'
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1}]}' -Header @{
                Link = "<$next>; rel=`"next`""
                'X-RateLimit-Used-CurrentRequest' = '1'
            })
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":2}]}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
        )

        $rows = @(Invoke-FsuPagedRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -PathSegments @('tickets') `
                -EnvelopeProperty tickets `
                -PSTypeName 'FreshservicePSU.Ticket' `
                -PerPage 1 `
                -Transport $probe.Transport)

        $rows.Count | Should -Be 2
        $rows.Id | Should -Be @(1, 2)
        $probe.State.Request.Count | Should -Be 2
        $probe.State.Request[1].Uri.AbsoluteUri | Should -Be $next
    }

    It 'stops before fetching another page once MaxRecords is reached' {
        $next = 'https://acme.freshservice.com/api/v2/tickets?page=2&per_page=2'
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1},{"id":2}]}' -Header @{
                Link = "<$next>; rel=`"next`""
                'X-RateLimit-Used-CurrentRequest' = '1'
            })
        )

        $rows = @(Invoke-FsuPagedRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -PathSegments @('tickets') `
                -EnvelopeProperty tickets `
                -PSTypeName 'FreshservicePSU.Ticket' `
                -PerPage 2 `
                -MaxRecords 2 `
                -Transport $probe.Transport)

        $rows.Count | Should -Be 2
        $probe.State.Request.Count | Should -Be 1
    }

    It 'warns when MaxRecords truncates results and a next link was present' {
        $next = 'https://acme.freshservice.com/api/v2/tickets?page=2&per_page=2'
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1},{"id":2}]}' -Header @{
                Link = "<$next>; rel=`"next`""
                'X-RateLimit-Used-CurrentRequest' = '1'
            })
        )

        $rows = @(Invoke-FsuPagedRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -PathSegments @('tickets') `
                -EnvelopeProperty tickets `
                -PSTypeName 'FreshservicePSU.Ticket' `
                -PerPage 2 `
                -MaxRecords 2 `
                -Transport $probe.Transport `
                -WarningVariable warnings -WarningAction SilentlyContinue)

        $rows.Count | Should -Be 2
        @($warnings).Count | Should -Be 1
        [string]$warnings[0] | Should -Match 'MaxRecords'
    }

    It 'warns when MaxRecords truncates results with leftover items on the current page' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1},{"id":2},{"id":3}]}' -Header @{
                'X-RateLimit-Used-CurrentRequest' = '1'
            })
        )

        $rows = @(Invoke-FsuPagedRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -PathSegments @('tickets') `
                -EnvelopeProperty tickets `
                -PSTypeName 'FreshservicePSU.Ticket' `
                -PerPage 3 `
                -MaxRecords 2 `
                -Transport $probe.Transport `
                -WarningVariable warnings -WarningAction SilentlyContinue)

        $rows.Count | Should -Be 2
        @($warnings).Count | Should -Be 1
    }

    It 'does not warn when MaxRecords is reached exactly at the end of data with no next link' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1},{"id":2}]}' -Header @{
                'X-RateLimit-Used-CurrentRequest' = '1'
            })
        )

        $rows = @(Invoke-FsuPagedRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -PathSegments @('tickets') `
                -EnvelopeProperty tickets `
                -PSTypeName 'FreshservicePSU.Ticket' `
                -PerPage 2 `
                -MaxRecords 2 `
                -Transport $probe.Transport `
                -WarningVariable warnings -WarningAction SilentlyContinue)

        $rows.Count | Should -Be 2
        @($warnings).Count | Should -Be 0
    }

    It 'does not warn when the record count stays under MaxRecords' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1}]}' -Header @{
                'X-RateLimit-Used-CurrentRequest' = '1'
            })
        )

        $rows = @(Invoke-FsuPagedRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -PathSegments @('tickets') `
                -EnvelopeProperty tickets `
                -PSTypeName 'FreshservicePSU.Ticket' `
                -PerPage 100 `
                -MaxRecords 1000 `
                -Transport $probe.Transport `
                -WarningVariable warnings -WarningAction SilentlyContinue)

        $rows.Count | Should -Be 1
        @($warnings).Count | Should -Be 0
    }

    It 'refuses a next link whose page exceeds 500' {
        $next = 'https://acme.freshservice.com/api/v2/tickets?page=501&per_page=100'
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1}]}' -Header @{
                Link = "<$next>; rel=`"next`""
                'X-RateLimit-Used-CurrentRequest' = '1'
            })
        )
        $caught = $null
        $rows = [System.Collections.Generic.List[object]]::new()
        try {
            Invoke-FsuPagedRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -PathSegments @('tickets') `
                -EnvelopeProperty tickets `
                -PSTypeName 'FreshservicePSU.Ticket' `
                -Transport $probe.Transport | ForEach-Object { $null = $rows.Add($_) }
        } catch {
            $caught = $_
        }

        $rows.Count | Should -Be 1
        $caught.FullyQualifiedErrorId | Should -Match 'PartialResults'
        $caught.Exception.Data['PagesCompleted'] | Should -Be 1
        $caught.Exception.Data['RecordsEmitted'] | Should -Be 1
        ($caught | Out-String) | Should -Not -Match 'page=501'
        ($caught | Out-String) | Should -Not -Match '"tickets"'
    }

    It 'wraps a later-page HTTP failure as PartialResults without the response body' {
        $next = 'https://acme.freshservice.com/api/v2/tickets?page=2&per_page=1'
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1}]}' -Header @{
                Link = "<$next>; rel=`"next`""
                'X-RateLimit-Used-CurrentRequest' = '1'
            })
            (New-FsuCannedHttpResponse -StatusCode 500 -Content '{"description":"secret-body-should-not-leak"}')
        )
        $caught = $null
        $context = New-FsuTestContext -ApiKey $apiKey -RetryPolicy (New-FsuRetryPolicy -MaxAttempts 1)
        try {
            $null = @(Invoke-FsuPagedRequest `
                    -Context $context `
                    -PathSegments @('tickets') `
                    -EnvelopeProperty tickets `
                    -PSTypeName 'FreshservicePSU.Ticket' `
                    -PerPage 1 `
                    -Transport $probe.Transport)
        } catch {
            $caught = $_
        }

        $caught.FullyQualifiedErrorId | Should -Match 'PartialResults'
        $caught.Exception.Data['PagesCompleted'] | Should -Be 1
        $caught.Exception.Data['RecordsEmitted'] | Should -Be 1
        ($caught | Out-String) | Should -Not -Match 'secret-body-should-not-leak'
    }

    It 'preserves the underlying page failure as the PartialResults InnerException with status/code discoverable' {
        $next = 'https://acme.freshservice.com/api/v2/tickets?page=2&per_page=1'
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1}]}' -Header @{
                Link = "<$next>; rel=`"next`""
                'X-RateLimit-Used-CurrentRequest' = '1'
            })
            (New-FsuCannedHttpResponse -StatusCode 403 -Content '{"description":"Access denied","errors":[{"field":"tickets","message":"access_denied","code":"access_denied"}]}')
        )
        $caught = $null
        $context = New-FsuTestContext -ApiKey $apiKey -RetryPolicy (New-FsuRetryPolicy -MaxAttempts 1)
        try {
            $null = @(Invoke-FsuPagedRequest `
                    -Context $context `
                    -PathSegments @('tickets') `
                    -EnvelopeProperty tickets `
                    -PSTypeName 'FreshservicePSU.Ticket' `
                    -PerPage 1 `
                    -Transport $probe.Transport)
        } catch {
            $caught = $_
        }

        $caught.FullyQualifiedErrorId | Should -Match 'PartialResults'
        $caught.Exception.InnerException | Should -Not -BeNullOrEmpty
        $caught.Exception.InnerException.Data['StatusCode'] | Should -Be 403
        $caught.Exception.Data['StatusCode'] | Should -Be 403
    }

    It 'rejects a next link that leaves the configured tenant base URI' {
        $next = 'https://attacker.example.com/api/v2/tickets?page=2'
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1}]}' -Header @{
                Link = "<$next>; rel=`"next`""
                'X-RateLimit-Used-CurrentRequest' = '1'
            })
        )
        $caught = $null
        try {
            $null = @(Invoke-FsuPagedRequest `
                    -Context (New-FsuTestContext -ApiKey $apiKey) `
                    -PathSegments @('tickets') `
                    -EnvelopeProperty tickets `
                    -PSTypeName 'FreshservicePSU.Ticket' `
                    -Transport $probe.Transport)
        } catch {
            $caught = $_
        }
        $caught.FullyQualifiedErrorId | Should -Match 'PartialResults'
    }
}
