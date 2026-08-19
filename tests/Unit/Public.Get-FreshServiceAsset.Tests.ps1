<#
.SYNOPSIS
    Unit tests for Get-FreshServiceAsset parameter mapping and Q13 output.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuAsset.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:moduleName = 'FreshservicePSU'
    Import-Module (Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1') -Force
    $script:context = New-FsuTestContext
}

AfterAll {
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FreshServiceAsset: export and parameters' {

    It 'is exported by the module' {
        (Get-Command -Name Get-FreshServiceAsset -Module $moduleName).Name | Should -Be 'Get-FreshServiceAsset'
    }

    It 'does not expose tenant, stage, identity, or secret parameters' {
        $names = (Get-Command Get-FreshServiceAsset).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'PrincipalId', 'AuthenticationType', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $names | Should -Not -Contain $_ }
    }
}

Describe 'ConvertTo-FsuAsset: Q13 contract' {

    It 'maps guaranteed asset properties' {
        $raw = [PSCustomObject]@{
            id = 10
            display_id = 11
            name = 'Macbook Pro'
            asset_tag = 'ASSET-9'
            asset_type_id = 25
            usage_type = 'permanent'
            impact = 'low'
            location_id = 3
            department_id = $null
            agent_id = $null
            user_id = 7
            group_id = 9
            assigned_on = '2014-07-26T06:55:04Z'
            created_at = '2019-03-07T09:27:09Z'
            updated_at = '2019-03-07T09:27:09Z'
            description = '13.3-inch display'
        }

        $asset = ConvertTo-FsuAsset -InputObject $raw
        $asset.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Asset'
        $asset.Id | Should -Be 10
        $asset.DisplayId | Should -Be 11
        $asset.Name | Should -Be 'Macbook Pro'
        $asset.AssetTag | Should -Be 'ASSET-9'
        $asset.AssetTypeId | Should -Be 25
        $asset.UserId | Should -Be 7
        $asset.CreatedAt | Should -BeOfType [datetime]
        $asset.CreatedAt.Kind | Should -Be ([System.DateTimeKind]::Utc)
    }
}

Describe 'Get-FreshServiceAsset: pipeline mapping' {

    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'reads one asset by DisplayId through GET /assets/{display_id}' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{
                id = 10; display_id = 11; name = 'Macbook Pro'; asset_tag = 'ASSET-9'
                asset_type_id = 25; usage_type = 'permanent'; impact = 'low'
            }
        }

        $result = Get-FreshServiceAsset -DisplayId 11
        $result.DisplayId | Should -Be 11
        $result.Name | Should -Be 'Macbook Pro'
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Asset'

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and
            $PathSegments[0] -eq 'assets' -and
            $PathSegments[1] -eq '11' -and
            $EnvelopeProperty -eq 'asset'
        }
    }

    It 'looks up an asset tag through a quoted filter' {
        Mock -ModuleName $moduleName Invoke-FsuNumberedPagedRequest {
            [PSCustomObject]@{ id = 10; display_id = 11; name = 'Macbook Pro'; asset_tag = 'ASSET-9' }
        }

        $null = Get-FreshServiceAsset -AssetTag 'ASSET-9'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuNumberedPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'assets' -and
            $QueryParameters['filter'] -eq '"asset_tag:''ASSET-9''"' -and
            $EnvelopeProperty -eq 'assets'
        }
    }

    It 'looks up a serial number through a quoted filter' {
        Mock -ModuleName $moduleName Invoke-FsuNumberedPagedRequest {
            [PSCustomObject]@{ id = 10; display_id = 11; name = 'Macbook Pro'; asset_tag = 'ASSET-9' }
        }

        $null = Get-FreshServiceAsset -SerialNumber 'SW12131133'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuNumberedPagedRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParameters['filter'] -eq '"serial_number:''SW12131133''"'
        }
    }

    It 'sends a validated filter through numbered paging' {
        Mock -ModuleName $moduleName Invoke-FsuNumberedPagedRequest {
            [PSCustomObject]@{ id = 65; display_id = 65; name = 'Asset-65'; asset_tag = 'ASSET-65' }
        }

        $result = Get-FreshServiceAsset -Filter "asset_state:'IN STOCK' AND location_id:3" -MaxRecords 50 -PerPage 30
        $result.DisplayId | Should -Be 65

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuNumberedPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'assets' -and
            $QueryParameters['filter'] -eq '"asset_state:''IN STOCK'' AND location_id:3"' -and
            $PerPage -eq 30 -and
            $MaxRecords -eq 50 -and
            $Operation -eq 'Get-FreshServiceAsset'
        }
    }

    It 'rejects an unbounded filter before transport' {
        Mock -ModuleName $moduleName Invoke-FsuNumberedPagedRequest { throw 'transport should not run' }
        { Get-FreshServiceAsset -Filter 'AND OR' } | Should -Throw '*field condition*'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuNumberedPagedRequest -Times 0
    }

    It 'rejects workspace_id in a filter before transport' {
        Mock -ModuleName $moduleName Invoke-FsuNumberedPagedRequest { throw 'transport should not run' }
        { Get-FreshServiceAsset -Filter 'workspace_id:2 AND location_id:3' } | Should -Throw '*workspace_id*'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuNumberedPagedRequest -Times 0
    }
}
