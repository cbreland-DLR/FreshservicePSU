<#
.SYNOPSIS
    Unit tests for Set-FreshServiceAsset.
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

Describe 'Set-FreshServiceAsset: export and parameters' {

    It 'is exported by the module' {
        (Get-Command -Name Set-FreshServiceAsset -Module $moduleName).Name | Should -Be 'Set-FreshServiceAsset'
    }

    It 'does not expose tenant, stage, identity, or secret parameters' {
        $names = (Get-Command Set-FreshServiceAsset).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'PrincipalId', 'AuthenticationType', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $names | Should -Not -Contain $_ }
    }

    It 'supports ShouldProcess' {
        (Get-Command Set-FreshServiceAsset).Parameters.ContainsKey('WhatIf') | Should -BeTrue
    }
}

Describe 'Set-FreshServiceAsset: pipeline mapping' {

    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'sends only bound vendor fields on PUT /assets/{display_id}' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{
                id = 10; display_id = 11; name = 'Macbook Pro 2'; asset_tag = 'ASSET-9'
                asset_type_id = 25; usage_type = 'loaner'; impact = 'low'
            }
        }

        $result = Set-FreshServiceAsset -DisplayId 11 -Name 'Macbook Pro 2' -UsageType loaner
        $result.Name | Should -Be 'Macbook Pro 2'
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Asset'

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            $PathSegments[0] -eq 'assets' -and
            $PathSegments[1] -eq '11' -and
            $Body['name'] -eq 'Macbook Pro 2' -and
            $Body['usage_type'] -eq 'loaner' -and
            $BoundParameterNames -contains 'name' -and
            $BoundParameterNames -contains 'usage_type' -and
            $BoundParameterNames -notcontains 'asset_tag' -and
            -not $Body.ContainsKey('asset_tag')
        }
    }

    It 'sends an explicit null relationship id' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 10; display_id = 11; name = 'Macbook Pro'; agent_id = $null }
        }

        $null = Set-FreshServiceAsset -DisplayId 11 -AgentId $null
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $BoundParameterNames -contains 'agent_id' -and
            $null -eq $Body['agent_id']
        }
    }

    It 'rejects an update with no property fields' {
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        { Set-FreshServiceAsset -DisplayId 11 } | Should -Throw '*updatable asset property*'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
    }

    It 'does not send HTTP when -WhatIf is set' {
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        Mock -ModuleName $moduleName Get-FsuExecutionContext { throw 'context should not run' }
        $null = Set-FreshServiceAsset -DisplayId 11 -Name 'Nope' -WhatIf
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
        Should -Invoke -ModuleName $moduleName -CommandName Get-FsuExecutionContext -Times 0
    }
}

Describe 'Set-FreshServiceAsset: Description JSON-null contract' {

    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'omits description when not bound' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 10; display_id = 11; name = 'Macbook Pro' }
        }
        $null = Set-FreshServiceAsset -DisplayId 11 -Name 'Macbook Pro'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $BoundParameterNames -notcontains 'description' -and
            -not $Body.ContainsKey('description')
        }
    }

    It 'sends an explicit JSON null when bound as $null' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 10; display_id = 11; description = $null }
        }
        $null = Set-FreshServiceAsset -DisplayId 11 -Description $null
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $BoundParameterNames -contains 'description' -and
            $Body.ContainsKey('description') -and
            $null -eq $Body['description']
        }
    }

    It 'sends a bound string description' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 10; display_id = 11; description = 'x' }
        }
        $null = Set-FreshServiceAsset -DisplayId 11 -Description 'x'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $Body['description'] -eq 'x'
        }
    }

    It 'rejects a non-string, non-null description with a normalized error' {
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        $caught = $null
        try {
            $null = Set-FreshServiceAsset -DisplayId 11 -Description 123
        } catch {
            $caught = $_
        }
        $caught | Should -Not -BeNullOrEmpty
        $caught.FullyQualifiedErrorId | Should -Match 'FreshservicePSU\.Asset\.InvalidDescription'
        $caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
    }
}
