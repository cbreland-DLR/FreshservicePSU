<#
.SYNOPSIS
    Unit tests for Slice B reference reads: groups, departments, agents, requesters.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuAgentGroup.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuDepartment.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuAgent.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuRequester.ps1')
    . (Join-Path $private 'Serialization/Get-FsuSingularEnvelopePayload.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:moduleName = 'FreshservicePSU'
    Import-Module (Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1') -Force
    $script:context = New-FsuTestContext
}

AfterAll {
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

Describe 'Slice B commands are exported without secret parameters' {
    It '<Name> is exported' -ForEach @(
        @{ Name = 'Get-FreshServiceAgentGroup' }
        @{ Name = 'Get-FreshServiceDepartment' }
        @{ Name = 'Get-FreshServiceAgent' }
        @{ Name = 'Get-FreshServiceRequester' }
    ) {
        (Get-Command -Name $Name -Module $moduleName).Name | Should -Be $Name
        $keys = (Get-Command $Name).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $keys | Should -Not -Contain $_ }
    }
}

Describe 'Q13 mapping' {
    It 'maps an agent group' {
        $group = ConvertTo-FsuAgentGroup -InputObject ([PSCustomObject]@{
                id = 1; name = 'Linux Support'; description = 'Linux'; restricted = $false
                escalate_to = 73; business_hours_id = $null
                created_at = '2014-01-08T02:23:41Z'; updated_at = '2020-01-08T02:23:41Z'
            })
        $group.PSObject.TypeNames | Should -Contain 'FreshservicePSU.AgentGroup'
        $group.Id | Should -Be 1
        $group.Name | Should -Be 'Linux Support'
        $group.CreatedAt | Should -BeOfType [datetime]
    }

    It 'maps a department' {
        $department = ConvertTo-FsuDepartment -InputObject ([PSCustomObject]@{
                id = 1; name = 'Sales'; description = 'Sales dept'; head_user_id = 5; prime_user_id = 7
                created_at = '2019-04-04T04:45:15Z'; updated_at = '2019-04-04T04:45:15Z'
            })
        $department.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Department'
        $department.Name | Should -Be 'Sales'
        $department.HeadUserId | Should -Be 5
    }

    It 'maps an agent' {
        $agent = ConvertTo-FsuAgent -InputObject ([PSCustomObject]@{
                id = 1434; first_name = 'Rubeus'; last_name = 'Hagrid'
                email = 'rubeus.hagrid@hogwarts.edu'; active = $true; job_title = 'Gamekeeper'
                department_ids = @(554); location_id = 34; reporting_manager_id = 32
            })
        $agent.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Agent'
        $agent.Email | Should -Be 'rubeus.hagrid@hogwarts.edu'
        $agent.Active | Should -BeTrue
        $agent.LocationId | Should -Be 34
    }

    It 'maps a requester' {
        $requester = ConvertTo-FsuRequester -InputObject ([PSCustomObject]@{
                id = 777; first_name = 'Harry'; last_name = 'Potter'
                primary_email = 'harry.potter@hogwarts.edu'; active = $true; job_title = 'Student'
                department_ids = @(554); location_id = 23; reporting_manager_id = 656
                is_agent = $false
            })
        $requester.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Requester'
        $requester.Email | Should -Be 'harry.potter@hogwarts.edu'
        $requester.Active | Should -BeTrue
        $requester.LocationId | Should -Be 23
        $requester.IsAgent | Should -BeFalse
    }

    It 'accepts a singular departments object envelope' {
        $body = [PSCustomObject]@{ departments = [PSCustomObject]@{ id = 1; name = 'Sales' } }
        (Get-FsuSingularEnvelopePayload -Body $body -PrimaryName department -AlternateName departments).name | Should -Be 'Sales'
    }
}

Describe 'Slice B pipeline mapping' {
    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'reads one agent group by Id' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 1; name = 'Linux Support'; description = 'Linux'; restricted = $false }
        }
        $result = Get-FreshServiceAgentGroup -Id 1
        $result.Name | Should -Be 'Linux Support'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'groups' -and $PathSegments[1] -eq '1' -and $EnvelopeProperty -eq 'group'
        }
    }

    It 'lists departments with a name filter' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            [PSCustomObject]@{ id = 1; name = 'Sales'; description = 'Sales' }
        }
        $null = Get-FreshServiceDepartment -Name 'Sales'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'departments' -and
            $QueryParameters['query'] -eq '"name:''Sales''"' -and
            $EnvelopeProperty -eq 'departments'
        }
    }

    It 'lists agents filtered by email and active' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            [PSCustomObject]@{ id = 1434; first_name = 'Ada'; last_name = 'Lovelace'; email = 'ada@contoso.com'; active = $true }
        }
        $null = Get-FreshServiceAgent -Email 'ada@contoso.com' -Active $true
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'agents' -and
            $QueryParameters['email'] -eq 'ada@contoso.com' -and
            $QueryParameters['active'] -eq 'true'
        }
    }

    It 'reads one requester by Id' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{
                id = 777; first_name = 'Harry'; last_name = 'Potter'
                primary_email = 'harry.potter@hogwarts.edu'; active = $true
            }
        }
        $result = Get-FreshServiceRequester -Id 777
        $result.Email | Should -Be 'harry.potter@hogwarts.edu'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'requesters' -and $PathSegments[1] -eq '777' -and $EnvelopeProperty -eq 'requester'
        }
    }

    It 'lists requesters filtered by email' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            [PSCustomObject]@{
                id = 777; first_name = 'Ada'; last_name = 'Lovelace'
                primary_email = 'ada@contoso.com'; active = $true
            }
        }
        $null = Get-FreshServiceRequester -Email 'ada@contoso.com'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'requesters' -and
            $QueryParameters['email'] -eq 'ada@contoso.com' -and
            -not $QueryParameters.Contains('include_agents')
        }
    }
}
