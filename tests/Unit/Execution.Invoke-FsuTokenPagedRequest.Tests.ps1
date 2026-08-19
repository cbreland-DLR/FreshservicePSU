<#
.SYNOPSIS
    Unit tests for Invoke-FsuTokenPagedRequest.
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
    . (Join-Path $private 'Execution/Invoke-FsuTokenPagedRequest.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:apiKey = 'test-api-key-DO-NOT-LEAK-token'
}

Describe 'Invoke-FsuTokenPagedRequest' {

    It 'follows next_page_url for a second page' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"activities":[{"content":"a"},{"content":"b"}],"next_page_url":"https://acme.freshservice.com/api/v2/tickets/152/activities?start_token=abc"}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
            (New-FsuCannedHttpResponse -Content '{"activities":[{"content":"c"}]}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
        )

        $rows = @(Invoke-FsuTokenPagedRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -PathSegments @('tickets', '152', 'activities') `
                -EnvelopeProperty activities `
                -PSTypeName 'FreshservicePSU.TicketActivity' `
                -Transport $probe.Transport)

        $rows.Count | Should -Be 3
        $probe.State.Request.Count | Should -Be 2
        $probe.State.Request[0].Uri.AbsolutePath | Should -Be '/api/v2/tickets/152/activities'
        $probe.State.Request[1].Uri.Query | Should -Match 'start_token=abc'
        ($rows | Out-String) | Should -Not -Match 'start_token'
    }

    It 'wraps a later-page failure as PartialResults without leaking the token' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"activities":[{"content":"a"},{"content":"b"}],"next_page_url":"https://acme.freshservice.com/api/v2/tickets/152/activities?start_token=secret-token"}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
            (New-FsuCannedHttpResponse -StatusCode 500 -Content '{"description":"secret-body-should-not-leak"}')
        )
        $context = New-FsuTestContext -ApiKey $apiKey -RetryPolicy (New-FsuRetryPolicy -MaxAttempts 1)
        $caught = $null
        try {
            $null = @(Invoke-FsuTokenPagedRequest `
                    -Context $context `
                    -PathSegments @('tickets', '152', 'activities') `
                    -EnvelopeProperty activities `
                    -PSTypeName 'FreshservicePSU.TicketActivity' `
                    -Transport $probe.Transport)
        } catch {
            $caught = $_
        }

        $caught.FullyQualifiedErrorId | Should -Match 'PartialResults'
        $caught.Exception.Data['PagesCompleted'] | Should -Be 1
        ($caught | Out-String) | Should -Not -Match 'secret-token'
        ($caught | Out-String) | Should -Not -Match 'secret-body-should-not-leak'
    }
}
