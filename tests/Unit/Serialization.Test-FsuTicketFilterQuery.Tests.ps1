<#
.SYNOPSIS
    Unit tests for Test-FsuTicketFilterQuery.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot '0.1.6/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Serialization/Test-FsuTicketFilterQuery.ps1')
}

Describe 'Test-FsuTicketFilterQuery' {

    It 'returns the unquoted query for a valid condition' {
        Test-FsuTicketFilterQuery -Query 'priority:4 OR status:2' | Should -Be 'priority:4 OR status:2'
    }

    It 'strips surrounding double quotes' {
        Test-FsuTicketFilterQuery -Query '"group_id:11"' | Should -Be 'group_id:11'
    }

    It 'accepts relational operators and quoted strings' {
        Test-FsuTicketFilterQuery -Query "priority:>3 AND email:'ada@contoso.com'" | Should -Be "priority:>3 AND email:'ada@contoso.com'"
    }

    It 'rejects an empty query' {
        { Test-FsuTicketFilterQuery -Query '   ' } | Should -Throw '*required*'
    }

    It 'rejects a query longer than 512 characters' {
        $long = 'priority:1 AND status:2' + (' AND tag:x' * 80)
        { Test-FsuTicketFilterQuery -Query $long } | Should -Throw '*512*'
    }

    It 'rejects an unbounded query with no field condition' {
        { Test-FsuTicketFilterQuery -Query 'AND OR' } | Should -Throw '*at least one field condition*'
    }

    It 'rejects workspace_id' {
        { Test-FsuTicketFilterQuery -Query 'workspace_id:2 AND status:2' } | Should -Throw '*workspace_id*'
    }

    It 'rejects unbalanced parentheses' {
        { Test-FsuTicketFilterQuery -Query '(priority:1 AND status:2' } | Should -Throw '*unbalanced*'
    }

    It 'rejects embedded double quotes' {
        { Test-FsuTicketFilterQuery -Query 'subject:"broken"' } | Should -Throw '*double quotes*'
    }
}
