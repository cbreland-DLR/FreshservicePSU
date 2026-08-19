<#
.SYNOPSIS
    Contract tests for Get-FreshServiceTicket request shape.
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

Describe 'Get-FreshServiceTicket contract' {

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
                Content = '{"ticket":{"id":266,"subject":"Ticket Title","status":2,"priority":3,"type":"Incident","requester_id":1000000678,"responder_id":null,"group_id":null,"department_id":null,"created_at":"2017-09-08T11:03:44Z","updated_at":"2017-09-08T11:03:44Z","due_by":"2017-09-08T23:03:44Z","fr_due_by":"2017-09-08T15:03:44Z"}}'
            }
        }
    }

    It 'sends GET /api/v2/tickets/266 with Basic auth and no correlation header' {
        $result = Get-FreshServiceTicket -TicketId 266
        $result.Id | Should -Be 266
        $result.Subject | Should -Be 'Ticket Title'
        $script:captured.Method | Should -Be 'GET'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/tickets/266'
        $script:captured.Header['Authorization'] | Should -Match '^Basic '
        @($script:captured.Header.Keys) | Should -Not -Contain 'X-Correlation-Id'
    }

    It 'sends include and requester_id on the list endpoint' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{
                Method = $Method
                Uri = $Uri
            }
            [PSCustomObject]@{
                StatusCode = 200
                ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '3' }
                Content = '{"tickets":[{"id":1,"subject":"A","status":2,"priority":1,"type":"Incident","requester_id":1230,"created_at":"2017-09-08T11:03:44Z","updated_at":"2017-09-08T11:03:44Z"}]}'
            }
        }

        $rows = @(Get-FreshServiceTicket -RequesterId 1230 -Include Requester)
        $rows.Count | Should -Be 1
        $rows[0].Id | Should -Be 1
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/tickets'
        $script:captured.Uri.Query | Should -Match 'requester_id=1230'
        $script:captured.Uri.Query | Should -Match 'include=requester'
        $script:captured.Uri.Query | Should -Match 'per_page=100'
    }
}
