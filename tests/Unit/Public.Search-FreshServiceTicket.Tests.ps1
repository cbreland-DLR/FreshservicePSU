<#
.SYNOPSIS
    Unit tests for Search-FreshServiceTicket.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:moduleName = 'FreshservicePSU'
    Import-Module (Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1') -Force
    $script:context = New-FsuTestContext
}

AfterAll {
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

Describe 'Search-FreshServiceTicket: export and parameters' {

    It 'is exported by the module' {
        (Get-Command -Name Search-FreshServiceTicket -Module $moduleName).Name | Should -Be 'Search-FreshServiceTicket'
    }

    It 'does not expose tenant, stage, identity, or secret parameters' {
        $names = (Get-Command Search-FreshServiceTicket).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'PrincipalId', 'AuthenticationType', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $names | Should -Not -Contain $_ }
    }
}

Describe 'Search-FreshServiceTicket: pipeline mapping' {

    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'sends a quoted query to GET /tickets/filter through numbered paging' {
        Mock -ModuleName $moduleName Invoke-FsuNumberedPagedRequest {
            [PSCustomObject]@{
                id = 506
                subject = 'New ticket with attachment'
                status = 2
                priority = 1
                type = 'Incident'
                requester_id = 3
            }
        }

        $result = Search-FreshServiceTicket -Query 'priority:4 OR priority:3' -MaxRecords 100 -PerPage 30
        $result.Id | Should -Be 506
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Ticket'

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuNumberedPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'tickets' -and
            $PathSegments[1] -eq 'filter' -and
            $QueryParameters['query'] -eq '"priority:4 OR priority:3"' -and
            $EnvelopeProperty -eq 'tickets' -and
            $PerPage -eq 30 -and
            $MaxRecords -eq 100 -and
            $Operation -eq 'Search-FreshServiceTicket'
        }
    }

    It 'rejects an unbounded query before transport' {
        Mock -ModuleName $moduleName Invoke-FsuNumberedPagedRequest { throw 'transport should not run' }
        { Search-FreshServiceTicket -Query 'AND OR' } | Should -Throw '*field condition*'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuNumberedPagedRequest -Times 0
    }
}
