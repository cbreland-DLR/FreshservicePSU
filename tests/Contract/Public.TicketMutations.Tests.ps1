<#
.SYNOPSIS
    Contract tests for ticket create, update, and note request bodies.
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

Describe 'Ticket mutation contracts' {
    BeforeEach {
        $script:captured = $null
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'sends POST /api/v2/tickets with only bound create fields' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{
                Method = $Method
                Uri = $Uri
                BodyText = if ($Body) { [System.Text.Encoding]::UTF8.GetString($Body) } else { $null }
            }
            [PSCustomObject]@{
                StatusCode = 201; ReasonPhrase = 'Created'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"ticket":{"id":265,"subject":"VPN","status":2,"priority":1,"type":"Incident","requester_id":1,"created_at":"2017-09-08T10:34:28Z","updated_at":"2017-09-08T10:34:28Z","due_by":"2017-09-11T10:34:28Z","fr_due_by":"2017-09-09T10:34:28Z"}}'
            }
        }
        $result = New-FreshServiceTicket -Email 'ada@contoso.com' -Subject 'VPN' -Description 'Cannot connect'
        $result.Id | Should -Be 265
        $script:captured.Method | Should -Be 'POST'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/tickets'
        $script:captured.Uri.Query | Should -Not -Match 'workspace_id'
        $script:captured.BodyText | Should -Match '"email":"ada@contoso.com"'
        $script:captured.BodyText | Should -Match '"subject":"VPN"'
        $script:captured.BodyText | Should -Not -Match 'cc_emails'
        $script:captured.BodyText | Should -Not -Match 'workspace_id'
        $script:captured.BodyText | Should -Not -Match 'priority'
    }

    It 'sends PUT /api/v2/tickets/265 with only the bound status' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{
                Method = $Method
                Uri = $Uri
                BodyText = if ($Body) { [System.Text.Encoding]::UTF8.GetString($Body) } else { $null }
            }
            [PSCustomObject]@{
                StatusCode = 200; ReasonPhrase = 'OK'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"ticket":{"id":265,"subject":"VPN","status":5,"priority":1,"type":"Incident","requester_id":1,"created_at":"2017-09-08T10:34:28Z","updated_at":"2017-09-08T10:34:28Z"}}'
            }
        }
        $result = Set-FreshServiceTicket -TicketId 265 -Status 5
        $result.Status | Should -Be 5
        $script:captured.Method | Should -Be 'PUT'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/tickets/265'
        $script:captured.BodyText | Should -Match '"status":5'
        $script:captured.BodyText | Should -Not -Match 'subject'
        $script:captured.BodyText | Should -Not -Match 'workspace_id'
    }

    It 'sends POST /api/v2/tickets/51/notes without user_id' {
        Mock -ModuleName $moduleName Send-FsuHttpRequest {
            $script:captured = [PSCustomObject]@{
                Method = $Method
                Uri = $Uri
                BodyText = if ($Body) { [System.Text.Encoding]::UTF8.GetString($Body) } else { $null }
            }
            [PSCustomObject]@{
                StatusCode = 201; ReasonPhrase = 'Created'
                Header = @{ 'X-RateLimit-Used-CurrentRequest' = '1' }
                Content = '{"conversation":{"id":4289856,"incoming":false,"private":true,"user_id":9,"body":"<div>Checked</div>","body_text":"Checked","ticket_id":51,"created_at":"2021-04-12T06:44:09Z","updated_at":"2021-04-12T06:44:09Z"}}'
            }
        }
        $result = Add-FreshServiceTicketNote -TicketId 51 -Body 'Checked' -Private $true
        $result.Private | Should -BeTrue
        $script:captured.Method | Should -Be 'POST'
        $script:captured.Uri.AbsolutePath | Should -Be '/api/v2/tickets/51/notes'
        $script:captured.BodyText | Should -Match '"body":"Checked"'
        $script:captured.BodyText | Should -Match '"private":true'
        $script:captured.BodyText | Should -Not -Match 'user_id'
    }
}
