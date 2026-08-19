<#
.SYNOPSIS
    Contract tests for Slice B reference-read request shapes.
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

Describe 'Slice B request contracts' {
    BeforeEach {
        $script:captured = $null
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'sends GET /api/v2/groups/1' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Method = $Method; Uri = $Uri; Header = $Header }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"group":{"id":1,"name":"Linux Support","description":"Linux","restricted":false,"created_at":"2014-01-08T02:23:41Z","updated_at":"2020-01-08T02:23:41Z"}}'
            }
        }
        $result = Get-FreshServiceAgentGroup -Id 1
        $result.Name | Should -Be 'Linux Support'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/groups/1'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
        $script:captured.Header['Authorization'] | Should -Match '^Basic '
    }

    It 'sends GET /api/v2/departments/1' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Method = $Method; Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"department":{"id":1,"name":"Sales","description":"Sales dept"}}'
            }
        }
        $result = Get-FreshServiceDepartment -Id 1
        $result.Name | Should -Be 'Sales'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/departments/1'
    }

    It 'sends GET /api/v2/agents with email filter' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Method = $Method; Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"agents":[{"id":1434,"first_name":"Ada","last_name":"Lovelace","email":"ada@contoso.com","active":true}]}'
            }
        }
        $rows = @(Get-FreshServiceAgent -Email 'ada@contoso.com')
        $rows[0].Email | Should -Be 'ada@contoso.com'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/agents'
        $script:captured.Uri.Query | Should -Match 'email=ada'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
    }

    It 'sends GET /api/v2/requesters/777' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Method = $Method; Uri = $Uri; Header = $Header }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"requester":{"id":777,"is_agent":false,"first_name":"Harry","last_name":"Potter","job_title":"Student","primary_email":"harry.potter@hogwarts.edu","department_ids":[554],"location_id":23,"reporting_manager_id":656,"active":true}}'
            }
        }
        $result = Get-FreshServiceRequester -Id 777
        $result.Email | Should -Be 'harry.potter@hogwarts.edu'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/requesters/777'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
        $script:captured.Uri.Query | Should -Not -Match 'include_agents'
    }

    It 'sends GET /api/v2/requesters with email filter' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Method = $Method; Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"requesters":[{"id":777,"first_name":"Ada","last_name":"Lovelace","primary_email":"ada@contoso.com","active":true}]}'
            }
        }
        $rows = @(Get-FreshServiceRequester -Email 'ada@contoso.com')
        $rows[0].Email | Should -Be 'ada@contoso.com'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/requesters'
        $script:captured.Uri.Query | Should -Match 'email=ada'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
        $script:captured.Uri.Query | Should -Not -Match 'include_agents'
    }
}
