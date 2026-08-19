<#
.SYNOPSIS
    Unit tests for Get-FreshServiceTicketField.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuTicketField.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:moduleName = 'FreshservicePSU'
    Import-Module (Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1') -Force
    $script:context = New-FsuTestContext
}

AfterAll {
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FreshServiceTicketField: export and parameters' {

    It 'is exported by the module' {
        (Get-Command -Name Get-FreshServiceTicketField -Module $moduleName).Name | Should -Be 'Get-FreshServiceTicketField'
    }

    It 'does not expose tenant, stage, identity, or secret parameters' {
        $names = (Get-Command Get-FreshServiceTicketField).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'PrincipalId', 'AuthenticationType', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $names | Should -Not -Contain $_ }
    }
}

Describe 'ConvertTo-FsuTicketField: Q13 contract' {

    It 'maps guaranteed field properties and choices' {
        $raw = [PSCustomObject]@{
            id = 54269
            name = 'status'
            label = 'Status'
            field_type = 'default_status'
            required_for_agents = $true
            default_field = $true
            choices = @([PSCustomObject]@{ value = 2; label = 'Open' })
            created_at = '2023-01-19T17:25:20Z'
            updated_at = '2023-01-19T17:25:20Z'
            description = 'Ticket status'
            workspace_id = 1
        }

        $field = ConvertTo-FsuTicketField -InputObject $raw
        $field.PSObject.TypeNames | Should -Contain 'FreshservicePSU.TicketField'
        $field.Id | Should -Be 54269
        $field.Name | Should -Be 'status'
        $field.Label | Should -Be 'Status'
        $field.FieldType | Should -Be 'default_status'
        $field.Required | Should -BeTrue
        $field.DefaultField | Should -BeTrue
        @($field.Choices).Count | Should -Be 1
        $field.CreatedAt | Should -BeOfType [datetime]
    }
}

Describe 'Get-FreshServiceTicketField: pipeline mapping' {

    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            [PSCustomObject]@{ id = 54268; name = 'requester'; label = 'Requester'; field_type = 'default_requester'; default_field = $true; required_for_agents = $true; choices = @(); created_at = '2023-01-19T17:25:20Z'; updated_at = '2023-01-19T17:25:20Z' }
            [PSCustomObject]@{ id = 54269; name = 'status'; label = 'Status'; field_type = 'default_status'; default_field = $true; required_for_agents = $true; choices = @(); created_at = '2023-01-19T17:25:20Z'; updated_at = '2023-01-19T17:25:20Z' }
        }
    }

    It 'lists ticket fields from GET /ticket_form_fields' {
        $rows = @(Get-FreshServiceTicketField)
        $rows.Count | Should -Be 2
        $rows[0].Name | Should -Be 'requester'
        $rows[1].PSObject.TypeNames | Should -Contain 'FreshservicePSU.TicketField'

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'ticket_form_fields' -and
            $EnvelopeProperty -eq 'ticket_fields' -and
            $Operation -eq 'Get-FreshServiceTicketField'
        }
    }

    It 'selects one field by Name after the list request' {
        $field = Get-FreshServiceTicketField -Name status
        $field.Id | Should -Be 54269
        $field.Name | Should -Be 'status'
    }

    It 'throws when the requested field Id is not in the form' {
        { Get-FreshServiceTicketField -Id 9 } | Should -Throw '*not found*'
    }
}
