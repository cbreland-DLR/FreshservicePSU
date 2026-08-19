<#
.SYNOPSIS
    Contract tests for Invoke-FsuRequest request and response shape
    (IMPLEMENTATION_PLAN.md Phase 4).
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
    . (Join-Path (Join-Path $repoRoot 'tests/Unit') 'FsuIdentityFixtures.ps1')

    $script:apiKey = 'test-api-key-DO-NOT-LEAK-pipe'
}

Describe 'Invoke-FsuRequest contract' {

    It 'uses the escaped path, encoded query, and JSON body the helpers produce' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 201 -Content '{"ticket":{"id":7,"subject":"café ticket"}}' -Header @{
                'X-RateLimit-Used-CurrentRequest' = '2'
                'X-RateLimit-Remaining' = '158'
                'X-RateLimit-Total' = '160'
                'X-Freshservice-Api-Version' = 'latest=v2'
            })
        )

        $result = Invoke-FsuRequest `
            -Context (New-FsuTestContext -ApiKey $apiKey) `
            -Method POST `
            -PathSegments @('tickets') `
            -QueryParameters @{ include = @('stats', 'requester') } `
            -Body @{ subject = 'café ticket'; due_by = [datetime]::SpecifyKind([datetime]'2026-08-16T15:00:00', 'Utc') } `
            -BoundParameterNames @('subject', 'due_by') `
            -EnvelopeProperty ticket `
            -PSTypeName 'FreshservicePSU.Ticket' `
            -Transport $probe.Transport

        $request = $probe.State.Request[0]
        $request.Method | Should -Be 'POST'
        $request.Uri.AbsolutePath | Should -Be '/api/v2/tickets'
        $request.Uri.Query | Should -Match 'include=stats'
        $request.Uri.Query | Should -Match 'include=requester'
        $bodyText = [Text.Encoding]::UTF8.GetString($request.Body)
        $bodyText | Should -Match 'café ticket'
        $bodyText | Should -Match '2026-08-16T15:00:00Z'
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Ticket'
        $result.subject | Should -Be 'café ticket'
    }

    It 'records actual request cost from X-RateLimit-Used-CurrentRequest on the envelope' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"ticket":{"id":1}}' -Header @{
                'X-RateLimit-Used-CurrentRequest' = '3'
                'X-RateLimit-Remaining' = '137'
                'X-RateLimit-Total' = '160'
            })
        )

        $envelope = Invoke-FsuRequest `
            -Context (New-FsuTestContext -ApiKey $apiKey) `
            -Method GET `
            -PathSegments @('tickets', '1') `
            -Transport $probe.Transport

        $envelope.RateLimit.UsedCurrentRequest | Should -Be 3
        $envelope.RateLimit.Remaining | Should -Be 137
        $envelope.RateLimit.Total | Should -Be 160
    }
}
