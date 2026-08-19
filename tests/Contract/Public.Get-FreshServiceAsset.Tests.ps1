<#
.SYNOPSIS
    Contract tests for Get-FreshServiceAsset request shapes.
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

Describe 'Get-FreshServiceAsset contract' {

    BeforeEach {
        $script:captured = $null
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'sends GET /api/v2/assets/11' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Method = $Method; Uri = $Uri; Header = $Header }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"asset":{"id":10,"display_id":11,"name":"Macbook Pro","asset_tag":"ASSET-9","asset_type_id":25,"usage_type":"permanent","impact":"low","location_id":null,"department_id":null,"agent_id":null,"user_id":null,"group_id":9,"assigned_on":"2014-07-26T06:55:04Z","created_at":"2019-03-07T09:27:09Z","updated_at":"2019-03-07T09:27:09Z"}}'
            }
        }
        $result = Get-FreshServiceAsset -DisplayId 11
        $result.DisplayId | Should -Be 11
        $result.Name | Should -Be 'Macbook Pro'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/assets/11'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
        $script:captured.Header['Authorization'] | Should -Match '^Basic '
    }

    It 'sends GET /api/v2/assets with a quoted asset-tag filter' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Method = $Method; Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"assets":[{"id":10,"display_id":11,"name":"Macbook Pro","asset_tag":"ASSET-9","asset_type_id":25,"usage_type":"permanent","impact":"low","created_at":"2019-03-07T09:27:09Z","updated_at":"2019-03-07T09:27:09Z"}],"total":1}'
            }
        }
        $rows = @(Get-FreshServiceAsset -AssetTag 'ASSET-9')
        $rows[0].AssetTag | Should -Be 'ASSET-9'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/assets'
        $script:captured.Uri.Query | Should -Match 'filter='
        $script:captured.Uri.Query | Should -Match 'asset_tag'
        $script:captured.Uri.Query | Should -Match 'ASSET-9'
        $script:captured.Uri.Query | Should -Match 'page=1'
        $script:captured.Uri.Query | Should -Match 'per_page=30'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
    }

    It 'sends GET /api/v2/assets with a validated filter and no workspace_id' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Method = $Method; Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"assets":[{"id":65,"display_id":65,"name":"Asset-65","asset_tag":"ASSET-65","asset_type_id":25,"usage_type":"permanent","impact":"low","created_at":"2018-08-03T07:48:11Z","updated_at":"2018-08-03T07:48:11Z"}],"total":1}'
            }
        }
        $rows = @(Get-FreshServiceAsset -Filter "asset_state:'IN STOCK' AND location_id:3")
        $rows[0].DisplayId | Should -Be 65
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/assets'
        $script:captured.Uri.Query | Should -Match 'filter='
        $script:captured.Uri.Query | Should -Match 'asset_state'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
    }
}
