<#
.SYNOPSIS
    Unit tests for Slice D reporting reads.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuRequestedItem.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuTask.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuApproval.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuTicketActivity.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuSLAPolicy.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuBusinessHour.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:moduleName = 'FreshservicePSU'
    Import-Module (Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1') -Force
    $script:context = New-FsuTestContext
}

AfterAll {
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

Describe 'Slice D commands are exported without secret parameters' {
    It '<Name> is exported' -ForEach @(
        @{ Name = 'Get-FreshServiceRequestedItem' }
        @{ Name = 'Get-FreshServiceTask' }
        @{ Name = 'Get-FreshServiceRequestApproval' }
        @{ Name = 'Search-FreshServiceApproval' }
        @{ Name = 'Get-FreshServiceTicketActivity' }
        @{ Name = 'Get-FreshServiceSLAPolicy' }
        @{ Name = 'Get-FreshServiceBusinessHour' }
    ) {
        (Get-Command -Name $Name -Module $moduleName).Name | Should -Be $Name
        $keys = (Get-Command $Name).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $keys | Should -Not -Contain $_ }
    }
}

Describe 'Slice D Q13 mapping' {
    It 'maps a requested item' {
        $item = ConvertTo-FsuRequestedItem -TicketId 1 -InputObject ([PSCustomObject]@{
                id = 1; service_item_id = 30; quantity = 1; stage = 1; loaned = $false
                cost_per_request = 0; is_parent = $true
                created_at = '2020-03-10T11:45:47Z'; updated_at = '2020-03-10T11:45:47Z'
            })
        $item.PSObject.TypeNames | Should -Contain 'FreshservicePSU.RequestedItem'
        $item.TicketId | Should -Be 1
        $item.ServiceItemId | Should -Be 30
        $item.Stage | Should -Be 1
    }

    It 'maps a ticket task' {
        $task = ConvertTo-FsuTask -TicketId 1 -InputObject ([PSCustomObject]@{
                id = 1; title = 'Supply lightsabers'; status = 1; agent_id = $null
                due_date = '2020-04-27T12:22:29Z'; created_at = '2020-04-27T12:22:29Z'
                updated_at = '2020-04-27T12:22:29Z'
            })
        $task.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Task'
        $task.Title | Should -Be 'Supply lightsabers'
        $task.DueDate | Should -BeOfType [datetime]
    }

    It 'maps an approval status object' {
        $approval = ConvertTo-FsuApproval -TicketId 20 -InputObject ([PSCustomObject]@{
                id = 7163764235; approver_id = 1001948400; approver_name = 'Alexander Schroeder'
                user_id = 1001948401; user_name = 'Rolanda Hooch'; level = 2
                approval_status = [PSCustomObject]@{ id = 0; name = 'requested' }
                created_at = '2022-12-08T11:52:41Z'; updated_at = '2023-01-09T08:48:23Z'
            })
        $approval.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Approval'
        $approval.ApprovalStatusName | Should -Be 'requested'
        $approval.TicketId | Should -Be 20
    }

    It 'maps ticket activity actor fields' {
        $row = ConvertTo-FsuTicketActivity -TicketId 152 -InputObject ([PSCustomObject]@{
                actor = [PSCustomObject]@{ id = 1434; name = 'Rubeus Hagrid' }
                content = ' restored this ticket from trash'
                sub_contents = @()
                created_at = '2021-06-15T05:28:10Z'
            })
        $row.PSObject.TypeNames | Should -Contain 'FreshservicePSU.TicketActivity'
        $row.ActorId | Should -Be 1434
        $row.ActorName | Should -Be 'Rubeus Hagrid'
        $row.CreatedAt | Should -BeOfType [datetime]
    }
}

Describe 'Slice D pipeline mapping' {
    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'lists requested items for a ticket' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            [PSCustomObject]@{ id = 1; service_item_id = 30; quantity = 1; stage = 1 }
        }
        $result = Get-FreshServiceRequestedItem -TicketId 1
        $result.ServiceItemId | Should -Be 30
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'tickets' -and $PathSegments[1] -eq '1' -and $PathSegments[2] -eq 'requested_items'
        }
    }

    It 'reads one ticket task by Id' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 1; title = 'Supply lightsabers'; status = 1 }
        }
        $result = Get-FreshServiceTask -TicketId 1 -Id 1
        $result.Title | Should -Be 'Supply lightsabers'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'tickets' -and $PathSegments[2] -eq 'tasks' -and $PathSegments[3] -eq '1'
        }
    }

    It 'rejects approval search without a required filter' {
        Mock -ModuleName $moduleName Invoke-FsuNumberedPagedRequest { throw 'transport should not run' }
        { Search-FreshServiceApproval -Level 1 } | Should -Throw '*at least one*'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuNumberedPagedRequest -Times 0
    }

    It 'searches approvals with parent=ticket and a required filter' {
        Mock -ModuleName $moduleName Invoke-FsuNumberedPagedRequest {
            [PSCustomObject]@{
                id = 1; parent_id = 12; approver_id = 123
                approval_status = [PSCustomObject]@{ id = 0; name = 'requested' }
            }
        }
        $null = Search-FreshServiceApproval -ApproverId 123 -Status requested
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuNumberedPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'approvals' -and
            $QueryParameters['parent'] -eq 'ticket' -and
            $QueryParameters['approver_id'] -eq 123 -and
            $QueryParameters['status'] -eq 'requested'
        }
    }

    It 'remaps require_feature on approval search' {
        Mock -ModuleName $moduleName Invoke-FsuNumberedPagedRequest {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Error.RequireFeature' -Message 'feature required' -Category PermissionDenied -StatusCode 403)
        }
        try {
            Search-FreshServiceApproval -Status requested
            $false | Should -BeTrue
        } catch {
            $_.FullyQualifiedErrorId | Should -Match 'SearchUnavailable'
        }
    }

    It 'reads ticket activity through token paging' {
        Mock -ModuleName $moduleName Invoke-FsuTokenPagedRequest {
            [PSCustomObject]@{ actor = [PSCustomObject]@{ id = 1; name = 'Ada' }; content = 'created ticket'; created_at = '2021-06-15T05:28:10Z' }
        }
        $result = Get-FreshServiceTicketActivity -TicketId 152 -MaxRecords 60
        $result.ActorName | Should -Be 'Ada'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuTokenPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'tickets' -and $PathSegments[2] -eq 'activities' -and $MaxRecords -eq 60
        }
    }

    It 'lists SLA policies' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            [PSCustomObject]@{ id = 344954; name = 'SLAPOLICY3'; is_default = $false; active = $true }
        }
        $result = Get-FreshServiceSLAPolicy
        $result.Name | Should -Be 'SLAPOLICY3'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'sla_policies'
        }
    }
}
