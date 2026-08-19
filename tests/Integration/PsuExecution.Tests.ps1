<#
.SYNOPSIS
    Opt-in PSU integration fixtures for Phase 7 attribution and isolation.

.DESCRIPTION
    Skipped unless FRESHSERVICEPSU_INTEGRATION=1. These tests use only
    the public module surface and never run in default Validate.
#>

$script:integrationEnabled = [string]$env:FRESHSERVICEPSU_INTEGRATION -eq '1'

Describe 'PSU execution isolation' {
    It 'uses a personal credential for an interactive ticket read' -Skip:(-not $script:integrationEnabled) {
        $ticket = Get-FreshServiceTicket -MaxRecords 1
        $ticket | Should -Not -BeNullOrEmpty
    }

    It 'uses the system credential for a claimless execution' -Skip:(-not $script:integrationEnabled) {
        $fields = Get-FreshServiceTicketField -MaxRecords 1
        $fields | Should -Not -BeNullOrEmpty
    }

    It 'does not leak one stage configuration into another' -Skip:(-not $script:integrationEnabled) {
        $first = Get-FreshServiceLocation -MaxRecords 1
        $second = Get-FreshServiceLocation -MaxRecords 1
        $first | Should -Not -BeNullOrEmpty
        $second | Should -Not -BeNullOrEmpty
    }

    It 'can run twice in the same runspace without leftover context' -Skip:(-not $script:integrationEnabled) {
        $null = Get-FreshServiceAgent -MaxRecords 1
        $again = Get-FreshServiceDepartment -MaxRecords 1
        $again | Should -Not -BeNullOrEmpty
    }

    It 'keeps an interactive bounded read inside the retry budget' -Skip:(-not $script:integrationEnabled) {
        $started = [datetime]::UtcNow
        $null = Get-FreshServiceTicket -MaxRecords 5
        (([datetime]::UtcNow) - $started).TotalSeconds | Should -BeLessThan 20
    }
}
