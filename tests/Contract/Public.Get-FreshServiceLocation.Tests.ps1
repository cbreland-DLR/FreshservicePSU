<#
.SYNOPSIS
    Contract tests for Get-FreshServiceLocation request shape.
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

Describe 'Get-FreshServiceLocation contract' {

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
                Content = '{"location":{"id":15,"name":"HQ","parent_location_id":2,"primary_contact_id":null,"created_at":"2018-12-18T10:03:48Z","updated_at":"2018-12-18T10:03:48Z"}}'
            }
        }
    }

    It 'sends GET /api/v2/locations/15 with Basic auth and no correlation header' {
        $result = Get-FreshServiceLocation -Id 15
        $result.Id | Should -Be 15
        $result.Name | Should -Be 'HQ'
        $script:captured.Method | Should -Be 'GET'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/locations/15'
        $script:captured.Header['Authorization'] | Should -Match '^Basic '
        @($script:captured.Header.Keys) | Should -Not -Contain 'X-Correlation-Id'
    }

    It 'sends an encoded name filter on the list endpoint' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{
                Method = $Method
                Uri = $Uri
            }
            [PSCustomObject]@{
                StatusCode = 200
                ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"locations":[{"id":8,"name":"United Kingdom","parent_location_id":2,"created_at":"2021-04-15T06:58:40Z","updated_at":"2021-04-15T06:58:40Z"}]}'
            }
        }

        $rows = @(Get-FreshServiceLocation -Name 'United Kingdom')
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be 'United Kingdom'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/locations'
        $script:captured.Uri.Query | Should -Match 'query='
        $script:captured.Uri.Query | Should -Match 'per_page=100'
    }
}
