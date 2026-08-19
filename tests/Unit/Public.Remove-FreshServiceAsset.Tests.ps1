<#
.SYNOPSIS
    Unit tests for Remove-FreshServiceAsset.
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

Describe 'Remove-FreshServiceAsset: export and parameters' {

    It 'is exported by the module' {
        (Get-Command -Name Remove-FreshServiceAsset -Module $moduleName).Name | Should -Be 'Remove-FreshServiceAsset'
    }

    It 'does not expose tenant, stage, identity, or secret parameters' {
        $names = (Get-Command Remove-FreshServiceAsset).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'PrincipalId', 'AuthenticationType', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $names | Should -Not -Contain $_ }
    }

    It 'supports ShouldProcess' {
        (Get-Command Remove-FreshServiceAsset).Parameters.ContainsKey('WhatIf') | Should -BeTrue
    }
}

Describe 'Remove-FreshServiceAsset: pipeline mapping' {

    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'sends DELETE /assets/{display_id} and writes no output' {
        Mock -ModuleName $moduleName Invoke-FsuRequest { [PSCustomObject]@{ StatusCode = 204 } }
        $result = Remove-FreshServiceAsset -DisplayId 11 -Confirm:$false
        $null -eq $result | Should -BeTrue
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and
            $PathSegments[0] -eq 'assets' -and
            $PathSegments[1] -eq '11'
        }
    }

    It 'does not send HTTP when -WhatIf is set' {
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        Mock -ModuleName $moduleName Get-FsuExecutionContext { throw 'context should not run' }
        $null = Remove-FreshServiceAsset -DisplayId 11 -WhatIf
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
        Should -Invoke -ModuleName $moduleName -CommandName Get-FsuExecutionContext -Times 0
    }
}
