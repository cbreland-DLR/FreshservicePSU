<#
.SYNOPSIS
    Contract tests for Slice C remaining asset-read request shapes.
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

Describe 'Slice C remaining request contracts' {
    BeforeEach {
        $script:captured = $null
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'sends GET /api/v2/asset_types/50' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Method = $Method; Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"asset_type":{"id":50,"name":"Chromebook","parent_asset_type_id":8,"description":"Asset type for all Chromebooks","visible":true,"created_at":"2019-02-14T10:03:02Z","updated_at":"2019-02-14T10:03:02Z"}}'
            }
        }
        $result = Get-FreshServiceAssetType -Id 50
        $result.Name | Should -Be 'Chromebook'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/asset_types/50'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
    }

    It 'sends GET /api/v2/assets/8/assignment-history' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Method = $Method; Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"assignment_history":[{"id":3,"user_id":2,"user_name":"System","assigned_on":"2024-01-01T04:05:36Z","created_at":"2024-01-01T04:05:36Z","updated_at":"2024-02-01T04:05:36Z","assigned_by":1,"assigned_by_name":"Support S","unassigned_by":2,"unassigned_by_name":"System","unassigned_on":"2024-01-31T04:05:36Z"}]}'
            }
        }
        $rows = @(Get-FreshServiceAssetAssignmentHistory -DisplayId 8)
        $rows[0].UserName | Should -Be 'System'
        $rows[0].DisplayId | Should -Be 8
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/assets/8/assignment-history'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
    }
}
