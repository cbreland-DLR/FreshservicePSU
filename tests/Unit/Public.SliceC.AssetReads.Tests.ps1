<#
.SYNOPSIS
    Unit tests for Slice C remaining reads: asset types and assignment history.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuAssetType.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuAssetAssignmentHistory.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:moduleName = 'FreshservicePSU'
    Import-Module (Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1') -Force
    $script:context = New-FsuTestContext
}

AfterAll {
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

Describe 'Slice C remaining commands are exported without secret parameters' {
    It '<Name> is exported' -ForEach @(
        @{ Name = 'Get-FreshServiceAssetType' }
        @{ Name = 'Get-FreshServiceAssetAssignmentHistory' }
    ) {
        (Get-Command -Name $Name -Module $moduleName).Name | Should -Be $Name
        $keys = (Get-Command $Name).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $keys | Should -Not -Contain $_ }
    }
}

Describe 'Q13 mapping' {
    It 'maps an asset type' {
        $type = ConvertTo-FsuAssetType -InputObject ([PSCustomObject]@{
                id = 50; name = 'Chromebook'; parent_asset_type_id = 8
                description = 'Asset type for all Chromebooks'; visible = $true
                created_at = '2019-02-14T10:03:02Z'; updated_at = '2019-02-14T10:03:02Z'
            })
        $type.PSObject.TypeNames | Should -Contain 'FreshservicePSU.AssetType'
        $type.Name | Should -Be 'Chromebook'
        $type.ParentAssetTypeId | Should -Be 8
        $type.Visible | Should -BeTrue
        $type.CreatedAt | Should -BeOfType [datetime]
    }

    It 'maps assignment history and stamps DisplayId' {
        $row = ConvertTo-FsuAssetAssignmentHistory -DisplayId 8 -InputObject ([PSCustomObject]@{
                id = 3; user_id = 2; user_name = 'System'
                assigned_on = '2024-01-01T04:05:36Z'; assigned_by = 1
                assigned_by_name = 'Support S'; unassigned_by = 2
                unassigned_by_name = 'System'; unassigned_on = '2024-01-31T04:05:36Z'
                created_at = '2024-01-01T04:05:36Z'; updated_at = '2024-02-01T04:05:36Z'
            })
        $row.PSObject.TypeNames | Should -Contain 'FreshservicePSU.AssetAssignmentHistory'
        $row.Id | Should -Be 3
        $row.DisplayId | Should -Be 8
        $row.UserName | Should -Be 'System'
        $row.AssignedOn | Should -BeOfType [datetime]
    }
}

Describe 'Slice C pipeline mapping' {
    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'reads one asset type by Id' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 50; name = 'Chromebook'; parent_asset_type_id = 8; visible = $true }
        }
        $result = Get-FreshServiceAssetType -Id 50
        $result.Name | Should -Be 'Chromebook'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'asset_types' -and $PathSegments[1] -eq '50' -and $EnvelopeProperty -eq 'asset_type'
        }
    }

    It 'lists asset types' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            [PSCustomObject]@{ id = 1; name = 'Services'; parent_asset_type_id = $null; visible = $true }
        }
        $null = Get-FreshServiceAssetType -MaxRecords 50
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'asset_types' -and
            $EnvelopeProperty -eq 'asset_types' -and
            $MaxRecords -eq 50
        }
    }

    It 'reads assignment history for a display id' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            [PSCustomObject]@{
                id = 3; user_id = 2; user_name = 'System'
                assigned_on = '2024-01-01T04:05:36Z'; assigned_by = 1
            }
        }
        $result = Get-FreshServiceAssetAssignmentHistory -DisplayId 8
        $result.DisplayId | Should -Be 8
        $result.UserId | Should -Be 2
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuPagedRequest -Times 1 -Exactly -ParameterFilter {
            $PathSegments[0] -eq 'assets' -and
            $PathSegments[1] -eq '8' -and
            $PathSegments[2] -eq 'assignment-history' -and
            $EnvelopeProperty -eq 'assignment_history'
        }
    }

    It 'remaps require_feature to AssignmentHistoryUnavailable' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Error.RequireFeature' -Message 'feature required' -Category PermissionDenied -StatusCode 403)
        }
        { Get-FreshServiceAssetAssignmentHistory -DisplayId 8 } | Should -Throw '*not available*'
        try {
            Get-FreshServiceAssetAssignmentHistory -DisplayId 8
        } catch {
            $_.FullyQualifiedErrorId | Should -Match 'AssignmentHistoryUnavailable'
        }
    }

    It 'does not remap a missing-asset 404' {
        Mock -ModuleName $moduleName Invoke-FsuPagedRequest {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Error.NotFound' -Message 'not found' -Category ObjectNotFound -StatusCode 404)
        }
        try {
            Get-FreshServiceAssetAssignmentHistory -DisplayId 8
            $false | Should -BeTrue
        } catch {
            $_.FullyQualifiedErrorId | Should -Match 'NotFound'
            $_.FullyQualifiedErrorId | Should -Not -Match 'AssignmentHistoryUnavailable'
        }
    }
}
