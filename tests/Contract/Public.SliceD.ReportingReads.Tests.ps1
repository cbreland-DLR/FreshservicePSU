<#
.SYNOPSIS
    Contract tests for Slice D reporting-read request shapes.
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

Describe 'Slice D request contracts' {
    BeforeEach {
        $script:captured = $null
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'sends GET /api/v2/tickets/1/requested_items' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"requested_items":[{"id":1,"service_item_id":30,"quantity":1,"stage":1,"loaned":false,"cost_per_request":0,"is_parent":true,"created_at":"2020-03-10T11:45:47Z","updated_at":"2020-03-10T11:45:47Z"}]}'
            }
        }
        $rows = @(Get-FreshServiceRequestedItem -TicketId 1)
        $rows[0].ServiceItemId | Should -Be 30
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/tickets/1/requested_items'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
    }

    It 'sends GET /api/v2/approvals with parent=ticket' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"approvals":[{"id":1,"parent":"ticket","parent_id":12,"approver_id":123,"approver_name":"Harry","approval_status":{"id":0,"name":"requested"},"created_at":"2020-04-10T04:12:33Z","updated_at":"2020-04-10T04:12:33Z"}],"total":1}'
            }
        }
        $rows = @(Search-FreshServiceApproval -ApproverId 123)
        $rows[0].ApproverId | Should -Be 123
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/approvals'
        $script:captured.Uri.Query | Should -Match 'parent=ticket'
        $script:captured.Uri.Query | Should -Match 'approver_id=123'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
    }

    It 'sends GET /api/v2/tickets/152/activities' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"activities":[{"actor":{"id":1434,"name":"Rubeus Hagrid"},"content":" restored this ticket from trash","sub_contents":[],"created_at":"2021-06-15T05:28:10Z"}]}'
            }
        }
        $rows = @(Get-FreshServiceTicketActivity -TicketId 152)
        $rows[0].ActorName | Should -Be 'Rubeus Hagrid'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/tickets/152/activities'
        $script:captured.Uri.Query | Should -Not -Match 'start_token'
    }

    It 'sends GET /api/v2/business_hours/1' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{ Uri = $Uri }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"business_hours":{"id":1,"name":"Default","description":"Default Business Calendar","is_default":true,"time_zone":"Chennai","created_at":"2019-05-07T13:58:42Z","updated_at":"2019-05-13T07:20:04Z"}}'
            }
        }
        $result = Get-FreshServiceBusinessHour -Id 1
        $result.Name | Should -Be 'Default'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/business_hours/1'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
    }
}
