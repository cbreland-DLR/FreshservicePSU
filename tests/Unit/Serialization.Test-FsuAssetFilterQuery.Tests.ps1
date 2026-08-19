<#
.SYNOPSIS
    Unit tests for Test-FsuAssetFilterQuery.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot '0.1.6/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Serialization/Test-FsuAssetFilterQuery.ps1')
}

Describe 'Test-FsuAssetFilterQuery' {

    It 'returns the unquoted query for a valid condition' {
        Test-FsuAssetFilterQuery -Query "asset_state:'IN STOCK'" | Should -Be "asset_state:'IN STOCK'"
    }

    It 'strips surrounding double quotes' {
        Test-FsuAssetFilterQuery -Query '"location_id:3"' | Should -Be 'location_id:3'
    }

    It 'accepts relational operators and quoted strings' {
        Test-FsuAssetFilterQuery -Query "created_at:>'2018-08-10' AND name:'dell'" | Should -Be "created_at:>'2018-08-10' AND name:'dell'"
    }

    It 'rejects an empty query' {
        { Test-FsuAssetFilterQuery -Query '   ' } | Should -Throw '*required*'
    }

    It 'rejects a query longer than 512 characters' {
        $long = "asset_state:'IN STOCK'" + (" AND name:'x'" * 80)
        { Test-FsuAssetFilterQuery -Query $long } | Should -Throw '*512*'
    }

    It 'rejects an unbounded query with no field condition' {
        { Test-FsuAssetFilterQuery -Query 'AND OR' } | Should -Throw '*at least one field condition*'
    }

    It 'rejects workspace_id' {
        { Test-FsuAssetFilterQuery -Query "workspace_id:2 AND asset_state:'IN STOCK'" } | Should -Throw '*workspace_id*'
    }

    It 'rejects unbalanced parentheses' {
        { Test-FsuAssetFilterQuery -Query "(asset_state:'IN STOCK' AND location_id:3" } | Should -Throw '*unbalanced*'
    }

    It 'rejects embedded double quotes' {
        { Test-FsuAssetFilterQuery -Query 'name:"broken"' } | Should -Throw '*double quotes*'
    }
}
