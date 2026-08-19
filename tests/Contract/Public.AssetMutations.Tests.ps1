<#
.SYNOPSIS
    Contract tests for Set-FreshServiceAsset and Remove-FreshServiceAsset.
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

Describe 'Asset mutation contracts' {

    BeforeEach {
        $script:captured = $null
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'sends PUT /api/v2/assets/11 with only the bound name field' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{
                Method = $Method
                Uri = $Uri
                BodyText = if ($Body) { [System.Text.Encoding]::UTF8.GetString($Body) } else { $null }
            }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"asset":{"id":10,"display_id":11,"name":"Macbook Pro 2","asset_tag":"ASSET-9","asset_type_id":25,"usage_type":"permanent","impact":"low","created_at":"2019-03-07T09:27:09Z","updated_at":"2019-03-07T09:27:09Z"}}'
            }
        }
        $result = Set-FreshServiceAsset -DisplayId 11 -Name 'Macbook Pro 2'
        $result.Name | Should -Be 'Macbook Pro 2'
        $script:captured.Method | Should -Be 'PUT'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/assets/11'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
        $script:captured.BodyText | Should -Match '"name":"Macbook Pro 2"'
        $script:captured.BodyText | Should -Not -Match 'asset_tag'
        $script:captured.BodyText | Should -Not -Match 'description'
    }

    It 'sends DELETE /api/v2/assets/11 with no body' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{
                Method = $Method
                Uri = $Uri
                Body = $Body
            }
            [PSCustomObject]@{
                StatusCode = 204; ReasonPhrase = 'No Content'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = ''
            }
        }
        $null = Remove-FreshServiceAsset -DisplayId 11 -Confirm:$false
        $script:captured.Method | Should -Be 'DELETE'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/assets/11'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
        $null -eq $script:captured.Body -or @($script:captured.Body).Count -eq 0 | Should -BeTrue
    }
}
