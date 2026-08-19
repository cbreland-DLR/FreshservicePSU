<#
.SYNOPSIS
    Unit tests for Get-FreshServiceTicket parameter mapping and Q13 output.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuTicket.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuEmbedQuery.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:moduleName = 'FreshservicePSU'
    Import-Module (Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1') -Force
    $script:context = New-FsuTestContext
}

AfterAll {
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FreshServiceTicket: export and parameters' {

    It 'is exported by the module' {
        (Get-Command -Name Get-FreshServiceTicket -Module $moduleName).Name | Should -Be 'Get-FreshServiceTicket'
    }

    It 'does not expose tenant, stage, identity, or secret parameters' {
        $names = (Get-Command Get-FreshServiceTicket).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'PrincipalId', 'AuthenticationType', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $names | Should -Not -Contain $_ }
    }
}

Describe 'ConvertTo-FsuTicket: Q13 contract' {

    It 'maps guaranteed ticket properties' {
        $raw = [PSCustomObject]@{
            id = 266
            subject = 'Ticket Title'
            status = 2
            priority = 3
            type = 'Incident'
            requester_id = 1000000678
            responder_id = $null
            group_id = 12
            department_id = $null
            created_at = '2017-09-08T11:03:44Z'
            updated_at = '2017-09-08T11:37:01Z'
            due_by = '2017-09-08T23:03:44Z'
            fr_due_by = '2017-09-08T15:03:44Z'
            description_text = 'this is a sample ticket'
            requester = [PSCustomObject]@{ email = 'ada@contoso.com' }
        }

        $ticket = ConvertTo-FsuTicket -InputObject $raw
        $ticket.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Ticket'
        $ticket.Id | Should -Be 266
        $ticket.Subject | Should -Be 'Ticket Title'
        $ticket.Status | Should -Be 2
        $ticket.Priority | Should -Be 3
        $ticket.RequesterId | Should -Be 1000000678
        $ticket.GroupId | Should -Be 12
        $ticket.CreatedAt | Should -BeOfType [datetime]
        $ticket.CreatedAt.Kind | Should -Be ([System.DateTimeKind]::Utc)
        $ticket.Requester.email | Should -Be 'ada@contoso.com'
    }
}

Describe 'ConvertTo-FsuEmbedQuery' {

    It 'joins validated embed names as a lowercase include value' {
        ConvertTo-FsuEmbedQuery -Include @('Requester', 'Stats') | Should -Be 'requester,stats'
    }

    It 'returns null when no embeds are supplied' {
        ConvertTo-FsuEmbedQuery -Include @() | Should -BeNullOrEmpty
    }
}

Describe 'Get-FreshServiceTicket: pipeline mapping' {

    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'reads one ticket by TicketId through GET /tickets/{id}' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{
                id = 266
                subject = 'Ticket Title'
                status = 2
                priority = 3
                type = 'Incident'
                requester_id = 1
                created_at = '2017-09-08T11:03:44Z'
                updated_at = '2017-09-08T11:03:44Z'
            }
        }

        $result = Get-FreshServiceTicket -TicketId 266
        $result.Id | Should -Be 266
        $result.Subject | Should -Be 'Ticket Title'
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Ticket'

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and
            $PathSegments[0] -eq 'tickets' -and
            $PathSegments[1] -eq '266' -and
            $EnvelopeProperty -eq 'ticket'
        }
    }

    It 'adds include and embed cost on a single-ticket read' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 266; subject = 'Ticket Title'; status = 2; priority = 3; type = 'Incident'; requester_id = 1 }
        }

        $null = Get-FreshServiceTicket -TicketId 266 -Include Requester, Conversations

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParameters['include'] -eq 'requester,conversations'
        }
    }

    It 'lists tickets with updated_since and list embed cost' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            [PSCustomObject]@{ id = 1; subject = 'A'; status = 2; priority = 1; type = 'Incident'; requester_id = 9 }
        }

        $since = [datetime]::SpecifyKind([datetime]'2026-08-15T00:00:00', 'Utc')
        $null = Get-FreshServiceTicket -UpdatedSince $since -Include Stats -MaxRecords 50 -PerPage 20

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'tickets' -and
            $QueryParameters['updated_since'] -eq '2026-08-15T00:00:00Z' -and
            $QueryParameters['include'] -eq 'stats' -and
            $PerPage -eq 20 -and
            $MaxRecords -eq 50
        }
    }

    It 'rejects Conversations embed on a list read before transport' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest { throw 'transport should not run' }

        { Get-FreshServiceTicket -Include Conversations } | Should -Throw '*TicketId*'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 0
    }
}
