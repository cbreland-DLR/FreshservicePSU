<#
.SYNOPSIS
    Contract tests for Search-FreshServiceTicket request shape.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path (Join-Path $repoRoot 'tests/Unit') 'FsuIdentityFixtures.ps1')

    $script:moduleName = 'FreshservicePSU'
    Import-Module (Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1') -Force
    $script:context = New-FsuTestContext
    $script:captured = $null
}

AfterAll {
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

Describe 'Search-FreshServiceTicket contract' {

    BeforeEach {
        $script:captured = $null
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{
                Method = $Method
                Uri = $Uri
                Header = $Header
            }
            [PSCustomObject]@{
                StatusCode = 200
                ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"tickets":[{"id":506,"subject":"New ticket with attachment","status":2,"priority":1,"type":"Incident","requester_id":3,"created_at":"2021-01-06T06:06:13Z","updated_at":"2021-04-29T09:03:21Z"}],"total":1}'
            }
        }
    }

    It 'sends GET /api/v2/tickets/filter with a quoted query and no correlation header' {
        $result = Search-FreshServiceTicket -Query 'priority:3'
        $result.Id | Should -Be 506
        $result.Subject | Should -Be 'New ticket with attachment'
        $script:captured.Method | Should -Be 'GET'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/tickets/filter'
        $script:captured.Uri.Query | Should -Match 'query='
        $script:captured.Uri.Query | Should -Match 'priority'
        $script:captured.Uri.Query | Should -Match 'page=1'
        $script:captured.Uri.Query | Should -Match 'per_page=30'
        $script:captured.Header['Authorization'] | Should -Match '^Basic '
        @($script:captured.Header.Keys) | Should -Not -Contain 'X-Correlation-Id'
    }
}
