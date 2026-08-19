<#
.SYNOPSIS
    Unit tests for Get-FreshServiceLocation parameter mapping and Q13 output.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuLocation.ps1')
    . (Join-Path $private 'Serialization/Get-FsuLocationEnvelopePayload.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:moduleName = 'FreshservicePSU'
    $script:manifestPath = Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1'
    Import-Module $manifestPath -Force

    $script:context = New-FsuTestContext
}

AfterAll {
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FreshServiceLocation: export and parameters' {

    It 'is exported by the module' {
        (Get-Command -Name Get-FreshServiceLocation -Module $moduleName).Name | Should -Be 'Get-FreshServiceLocation'
    }

    It 'does not expose tenant, stage, identity, or secret parameters' {
        $names = (Get-Command Get-FreshServiceLocation).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'PrincipalId', 'AuthenticationType', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $names | Should -Not -Contain $_ }
    }
}

Describe 'ConvertTo-FsuLocation: Q13 contract' {

    It 'maps guaranteed properties and leaves extra vendor fields non-contractual' {
        $raw = [PSCustomObject]@{
            id = 15
            name = 'HQ'
            parent_location_id = 2
            primary_contact_id = $null
            created_at = '2018-12-18T10:03:48Z'
            updated_at = '2018-12-18T10:03:48Z'
            address = [PSCustomObject]@{ city = 'San Bruno' }
            contact_name = 'Ada'
            email = 'ada@contoso.com'
            workspace_id = 1
        }

        $location = ConvertTo-FsuLocation -InputObject $raw
        $location.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Location'
        $location.Id | Should -Be 15
        $location.Name | Should -Be 'HQ'
        $location.ParentLocationId | Should -Be 2
        $null -eq $location.PrimaryContactId | Should -BeTrue
        $location.CreatedAt | Should -BeOfType [datetime]
        $location.CreatedAt.Kind | Should -Be ([System.DateTimeKind]::Utc)
        $location.Address.city | Should -Be 'San Bruno'
        $location.ContactName | Should -Be 'Ada'
    }
}

Describe 'Get-FsuLocationEnvelopePayload' {

    It 'prefers the location envelope' {
        $body = [PSCustomObject]@{ location = [PSCustomObject]@{ id = 1; name = 'A' } }
        (Get-FsuLocationEnvelopePayload -Body $body).id | Should -Be 1
    }

    It 'accepts a singular locations object from the view sample' {
        $body = [PSCustomObject]@{ locations = [PSCustomObject]@{ id = 2; name = 'B' } }
        (Get-FsuLocationEnvelopePayload -Body $body).name | Should -Be 'B'
    }

    It 'rejects a locations array on a single-object read' {
        $list = [System.Collections.Generic.List[object]]::new()
        $null = $list.Add([PSCustomObject]@{ id = 1 })
        $null = $list.Add([PSCustomObject]@{ id = 2 })
        $body = [PSCustomObject]@{ locations = $list }
        { Get-FsuLocationEnvelopePayload -Body $body } | Should -Throw '*list*'
    }
}

Describe 'Get-FreshServiceLocation: pipeline mapping' {

    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'reads one location by Id through GET /locations/{id}' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{
                PSTypeName = 'Freshservice.Response'
                Body = [PSCustomObject]@{ location = [PSCustomObject]@{ id = 15; name = 'HQ'; created_at = '2018-12-18T10:03:48Z'; updated_at = '2018-12-18T10:03:48Z'; parent_location_id = $null; primary_contact_id = $null } }
            }
        }

        $result = Get-FreshServiceLocation -Id 15
        $result.Id | Should -Be 15
        $result.Name | Should -Be 'HQ'
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Location'

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and
            $PathSegments[0] -eq 'locations' -and
            $PathSegments[1] -eq '15' -and
            $Operation -eq 'Get-FreshServiceLocation'
        }
    }

    It 'lists locations and sends a name filter query' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            [PSCustomObject]@{ id = 8; name = 'United Kingdom'; parent_location_id = 2; primary_contact_id = $null; created_at = '2021-04-15T06:58:40Z'; updated_at = '2021-04-15T06:58:40Z' }
        }

        $result = Get-FreshServiceLocation -Name 'United Kingdom' -MaxRecords 20 -PerPage 30
        $result.Name | Should -Be 'United Kingdom'

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'locations' -and
            $QueryParameters['query'] -eq "name:'United Kingdom'" -and
            $PerPage -eq 30 -and
            $MaxRecords -eq 20 -and
            $EnvelopeProperty -eq 'locations'
        }
    }
}
