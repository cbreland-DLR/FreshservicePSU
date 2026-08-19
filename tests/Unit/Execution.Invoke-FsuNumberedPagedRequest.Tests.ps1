<#
.SYNOPSIS
    Unit tests for Invoke-FsuNumberedPagedRequest.
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
    . (Join-Path $private 'Execution/Invoke-FsuNumberedPagedRequest.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:apiKey = 'test-api-key-DO-NOT-LEAK-pipe'
}

Describe 'Invoke-FsuNumberedPagedRequest' {

    It 'requests page 2 when the first page is full and total says more remain' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1},{"id":2}],"total":3}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":3}],"total":3}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
        )

        $rows = @(Invoke-FsuNumberedPagedRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -PathSegments @('tickets', 'filter') `
                -QueryParameters @{ query = '"priority:1"' } `
                -EnvelopeProperty tickets `
                -PSTypeName 'FreshservicePSU.Ticket' `
                -PerPage 2 `
                -Transport $probe.Transport)

        $rows.Count | Should -Be 3
        $probe.State.Request.Count | Should -Be 2
        $probe.State.Request[0].Uri.Query | Should -Match 'page=1'
        $probe.State.Request[1].Uri.Query | Should -Match 'page=2'
    }

    It 'wraps a later-page failure as PartialResults' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1},{"id":2}],"total":4}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
            (New-FsuCannedHttpResponse -StatusCode 500 -Content '{"description":"secret-body-should-not-leak"}')
        )
        $context = New-FsuTestContext -ApiKey $apiKey -RetryPolicy (New-FsuRetryPolicy -MaxAttempts 1)
        $caught = $null
        try {
            $null = @(Invoke-FsuNumberedPagedRequest `
                    -Context $context `
                    -PathSegments @('tickets', 'filter') `
                    -EnvelopeProperty tickets `
                    -PSTypeName 'FreshservicePSU.Ticket' `
                    -PerPage 2 `
                    -Transport $probe.Transport)
        } catch {
            $caught = $_
        }

        $caught.FullyQualifiedErrorId | Should -Match 'PartialResults'
        $caught.Exception.Data['PagesCompleted'] | Should -Be 1
        ($caught | Out-String) | Should -Not -Match 'secret-body-should-not-leak'
    }

    It 'preserves the underlying page failure as the PartialResults InnerException with status/code discoverable' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"tickets":[{"id":1},{"id":2}],"total":4}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
            (New-FsuCannedHttpResponse -StatusCode 403 -Content '{"description":"Access denied","errors":[{"field":"tickets","message":"access_denied","code":"access_denied"}]}')
        )
        $context = New-FsuTestContext -ApiKey $apiKey -RetryPolicy (New-FsuRetryPolicy -MaxAttempts 1)
        $caught = $null
        try {
            $null = @(Invoke-FsuNumberedPagedRequest `
                    -Context $context `
                    -PathSegments @('tickets', 'filter') `
                    -EnvelopeProperty tickets `
                    -PSTypeName 'FreshservicePSU.Ticket' `
                    -PerPage 2 `
                    -Transport $probe.Transport)
        } catch {
            $caught = $_
        }

        $caught.FullyQualifiedErrorId | Should -Match 'PartialResults'
        $caught.Exception.InnerException | Should -Not -BeNullOrEmpty
        $caught.Exception.InnerException.Data['StatusCode'] | Should -Be 403
        $caught.Exception.Data['StatusCode'] | Should -Be 403
    }
}
