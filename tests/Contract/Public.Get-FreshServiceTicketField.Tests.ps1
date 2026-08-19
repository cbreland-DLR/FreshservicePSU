<#
.SYNOPSIS
    Contract tests for Get-FreshServiceTicketField request shape.
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

Describe 'Get-FreshServiceTicketField contract' {

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
                Content = '{"ticket_fields":[{"id":54269,"name":"status","label":"Status","field_type":"default_status","default_field":true,"required_for_agents":true,"choices":[],"created_at":"2023-01-19T17:25:20Z","updated_at":"2023-01-19T17:25:20Z"}]}'
            }
        }
    }

    It 'sends GET /api/v2/ticket_form_fields with Basic auth and no workspace_id' {
        $rows = @(Get-FreshServiceTicketField)
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be 'status'
        $script:captured.Method | Should -Be 'GET'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/ticket_form_fields'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
        $script:captured.Header['Authorization'] | Should -Match '^Basic '
        @($script:captured.Header.Keys) | Should -Not -Contain 'X-Correlation-Id'
    }
}
