<#
.SYNOPSIS
    Unit tests for Invoke-FsuRequest (ARCHITECTURE.md §11).
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
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:apiKey = 'test-api-key-DO-NOT-LEAK-pipe'
    $script:expectedBasic = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script:apiKey + ':X'))
}

Describe 'Invoke-FsuRequest: success path' {

    It 'extracts the named envelope and applies PSTypeName' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"ticket":{"id":42,"subject":"Hello"}}' -Header @{
                'X-RateLimit-Used-CurrentRequest' = '1'
                'X-RateLimit-Remaining' = '499'
                'X-RateLimit-Total' = '500'
                'X-Freshservice-Api-Version' = 'latest=v2'
            })
        )
        $result = Invoke-FsuRequest `
            -Context (New-FsuTestContext -ApiKey $apiKey) `
            -Method GET `
            -PathSegments @('tickets', '42') `
            -EnvelopeProperty ticket `
            -PSTypeName 'FreshservicePSU.Ticket' `
            -Transport $probe.Transport

        $result.id | Should -Be 42
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Ticket'
        $probe.State.Request.Count | Should -Be 1
        $probe.State.Request[0].Method | Should -Be 'GET'
        $probe.State.Request[0].Uri.AbsolutePath | Should -Be '/api/v2/tickets/42'
    }

    It 'returns the response envelope when no EnvelopeProperty is supplied' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 204 -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
        )
        $result = Invoke-FsuRequest `
            -Context (New-FsuTestContext -ApiKey $apiKey) `
            -Method DELETE `
            -PathSegments @('tickets', '42') `
            -Transport $probe.Transport

        $result.PSObject.TypeNames | Should -Contain 'Freshservice.Response'
        $result.StatusCode | Should -Be 204
        $result.CorrelationId | Should -Be 'corr-pipe-1'
    }

    It 'emits one Success audit event on the information stream and nothing on success output besides the result' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"ticket":{"id":1}}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
        )
        $info = $null
        $result = Invoke-FsuRequest `
            -Context (New-FsuTestContext -ApiKey $apiKey) `
            -Method GET `
            -PathSegments @('tickets', '1') `
            -EnvelopeProperty ticket `
            -PSTypeName 'FreshservicePSU.Ticket' `
            -Transport $probe.Transport `
            -InformationVariable info

        $result.id | Should -Be 1
        @($info).Count | Should -Be 1
        $info[0].Tags | Should -Contain 'FreshservicePSU.Audit'
        $info[0].MessageData.Outcome | Should -Be 'Success'
    }
}

Describe 'Invoke-FsuRequest: request shape and redaction' {

    It 'sends Basic authorization and no correlation header' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"ticket":{"id":1}}')
        )
        $null = Invoke-FsuRequest `
            -Context (New-FsuTestContext -ApiKey $apiKey) `
            -Method GET `
            -PathSegments @('tickets', '1') `
            -EnvelopeProperty ticket `
            -PSTypeName 'FreshservicePSU.Ticket' `
            -Transport $probe.Transport

        $headers = $probe.State.Request[0].Header
        $headers['Authorization'] | Should -Be $expectedBasic
        $headers['Accept'] | Should -Be 'application/json'
        @($headers.Keys) | Should -Not -Contain 'X-Correlation-Id'
        @($headers.Keys) | Should -Not -Contain 'X-Request-Id'
        @($headers.Keys) | Should -Not -Contain 'Correlation-Id'
    }

    It 'serializes only bound POST fields as JSON' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 201 -Content '{"ticket":{"id":9}}')
        )
        $null = Invoke-FsuRequest `
            -Context (New-FsuTestContext -ApiKey $apiKey) `
            -Method POST `
            -PathSegments @('tickets') `
            -Body @{ subject = 'Created'; ignored = 'nope' } `
            -BoundParameterNames @('subject') `
            -EnvelopeProperty ticket `
            -PSTypeName 'FreshservicePSU.Ticket' `
            -Transport $probe.Transport

        $json = [Text.Encoding]::UTF8.GetString($probe.State.Request[0].Body)
        $json | Should -Match 'Created'
        $json | Should -Not -Match 'ignored'
        $json | Should -Not -Match 'nope'
    }

    It 'rejects a continuation URI that only shares the base path text prefix' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{}')
        )

        { Invoke-FsuRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -Method GET `
                -Uri ([uri]'https://acme.freshservice.com/api/v20/tickets?page=2') `
                -Transport $probe.Transport } | Should -Throw -ErrorId '*UntrustedUri*'

        $probe.State.Request.Count | Should -Be 0
    }

    It 'does not put the API key, Basic token, or response body into errors or audit events' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 401 -Content '{"code":"invalid_credentials","message":"nope"}')
        )
        $info = $null
        $caught = $null
        try {
            Invoke-FsuRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -Method GET `
                -PathSegments @('tickets', '1') `
                -Transport $probe.Transport `
                -InformationVariable info
        } catch {
            $caught = $_
        }

        $caught | Should -Not -BeNullOrEmpty
        $text = @($caught | Out-String) + @($info | Out-String)
        $text | Should -Not -Match ([regex]::Escape($apiKey))
        $text | Should -Not -Match ([regex]::Escape($expectedBasic))
        $text | Should -Not -Match 'sk_live'
    }
}

Describe 'Invoke-FsuRequest: retry, limiter, and uncertain outcome' {

    It 'retries a GET after 429 using Retry-After seconds and then succeeds' {
        $clock = [pscustomobject]@{ Now = [datetime]::SpecifyKind([datetime]'2026-08-16T12:00:00', 'Utc') }
        $waits = [System.Collections.Generic.List[double]]::new()
        $getTimestamp = { $clock.Now }.GetNewClosure()
        $wait = {
            param($Seconds)
            $null = $waits.Add([double]$Seconds)
            $clock.Now = $clock.Now.AddSeconds($Seconds)
        }.GetNewClosure()
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 429 -Header @{ 'Retry-After' = '2'; 'X-RateLimit-Used-CurrentRequest' = '0' })
            (New-FsuCannedHttpResponse -Content '{"ticket":{"id":1}}' -Header @{ 'X-RateLimit-Used-CurrentRequest' = '1' })
        )

        $result = Invoke-FsuRequest `
            -Context (New-FsuTestContext -ApiKey $apiKey) `
            -Method GET `
            -PathSegments @('tickets', '1') `
            -EnvelopeProperty ticket `
            -PSTypeName 'FreshservicePSU.Ticket' `
            -Transport $probe.Transport `
            -GetTimestamp $getTimestamp `
            -GetJitterFraction { 0.0 } `
            -Wait $wait

        $result.id | Should -Be 1
        $probe.State.Request.Count | Should -Be 2
        $waits.Count | Should -Be 1
        $waits[0] | Should -Be 2
    }

    It 'retries a POST after 429 because the request was not processed' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 429 -Header @{ 'Retry-After' = '1' })
            (New-FsuCannedHttpResponse -StatusCode 201 -Content '{"ticket":{"id":3}}')
        )
        $result = Invoke-FsuRequest `
            -Context (New-FsuTestContext -ApiKey $apiKey) `
            -Method POST `
            -PathSegments @('tickets') `
            -Body @{ subject = 'x' } `
            -BoundParameterNames @('subject') `
            -EnvelopeProperty ticket `
            -PSTypeName 'FreshservicePSU.Ticket' `
            -Transport $probe.Transport `
            -GetJitterFraction { 0.0 } `
            -Wait { }

        $result.id | Should -Be 3
        $probe.State.Request.Count | Should -Be 2
    }

    It 'does not retry a POST timeout and returns UncertainOutcome' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.Timeout' -Message 'timed out' -Category OperationTimeout)
        )
        $caught = $null
        try {
            Invoke-FsuRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -Method POST `
                -PathSegments @('tickets') `
                -Body @{ subject = 'x' } `
                -BoundParameterNames @('subject') `
                -Transport $probe.Transport `
                -Wait { }
        } catch {
            $caught = $_
        }

        $caught.FullyQualifiedErrorId | Should -Match 'UncertainOutcome'
        $probe.State.Request.Count | Should -Be 1
    }

    It 'does not retry a POST after HTTP 408 and returns UncertainOutcome' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 408)
        )
        $caught = $null
        try {
            Invoke-FsuRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -Method POST `
                -PathSegments @('tickets') `
                -Body @{ subject = 'x' } `
                -BoundParameterNames @('subject') `
                -Transport $probe.Transport `
                -Wait { }
        } catch {
            $caught = $_
        }

        $caught.FullyQualifiedErrorId | Should -Match 'UncertainOutcome'
        $probe.State.Request.Count | Should -Be 1
    }

    It 'retries a GET after a non-JSON 503 response' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 503 -Content '<html>maintenance</html>')
            (New-FsuCannedHttpResponse -Content '{"ticket":{"id":1}}')
        )

        $result = Invoke-FsuRequest `
            -Context (New-FsuTestContext -ApiKey $apiKey) `
            -Method GET `
            -PathSegments @('tickets', '1') `
            -EnvelopeProperty ticket `
            -PSTypeName 'FreshservicePSU.Ticket' `
            -Transport $probe.Transport `
            -GetJitterFraction { 0.0 } `
            -Wait { }

        $result.id | Should -Be 1
        $probe.State.Request.Count | Should -Be 2
    }

    It 'does not retry invalid_credentials and does not switch identity' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 401 -Content '{"code":"invalid_credentials","message":"nope"}')
        )
        { Invoke-FsuRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -Method GET `
                -PathSegments @('tickets', '1') `
                -Transport $probe.Transport } | Should -Throw
        $probe.State.Request.Count | Should -Be 1
    }

    It 'surfaces require_feature as a distinct error' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 403 -Content '{"errors":[{"code":"require_feature","message":"not enabled"}]}')
        )
        $caught = $null
        try {
            Invoke-FsuRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -Method GET `
                -PathSegments @('tickets', '1') `
                -Transport $probe.Transport
        } catch {
            $caught = $_
        }
        $caught.FullyQualifiedErrorId | Should -Match 'RequireFeature'
    }

    It 'marks 405 as a request-construction defect' {
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -StatusCode 405 -Content '')
        )
        $caught = $null
        try {
            Invoke-FsuRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -Method GET `
                -PathSegments @('tickets', '1') `
                -Transport $probe.Transport
        } catch {
            $caught = $_
        }
        $caught.FullyQualifiedErrorId | Should -Match 'RequestDefect'
    }

    It 'cancels before send and does not retry' {
        $cts = [System.Threading.CancellationTokenSource]::new()
        $cts.Cancel()
        $probe = New-FsuScriptedTransport -Response @(
            (New-FsuCannedHttpResponse -Content '{"ticket":{"id":1}}')
        )
        { Invoke-FsuRequest `
                -Context (New-FsuTestContext -ApiKey $apiKey) `
                -Method GET `
                -PathSegments @('tickets', '1') `
                -Transport $probe.Transport `
                -CancellationToken $cts.Token } | Should -Throw '*cancelled*'
        $probe.State.Request.Count | Should -Be 0
    }
}
