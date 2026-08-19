<#
.SYNOPSIS
    Unit tests for Get-FsuCallerVariable.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot '0.1.6/Private/Hosts/PowerShellUniversal/Get-FsuCallerVariable.ps1')
}

Describe 'Get-FsuCallerVariable' {

    It 'finds a variable defined in a parent scope' {
        function Invoke-FsuCallerLookupProbe {
            Get-FsuCallerVariable -Name 'FsuProbeVariable'
        }

        $FsuProbeVariable = 'top-of-scope-value'
        $result = Invoke-FsuCallerLookupProbe

        $result.Found | Should -BeTrue
        $result.Value | Should -Be 'top-of-scope-value'
    }

    It 'reports Found=$false for a name that does not exist anywhere in scope' {
        $result = Get-FsuCallerVariable -Name 'FsuDefinitelyDoesNotExist12345'
        $result.Found | Should -BeFalse
        $result.Value | Should -BeNullOrEmpty
    }

    It 'reports Found=$true with a $null value when the variable exists but is $null' {
        function Invoke-FsuCallerLookupProbe {
            Get-FsuCallerVariable -Name 'FsuProbeNullVariable'
        }

        $FsuProbeNullVariable = $null
        $result = Invoke-FsuCallerLookupProbe

        $result.Found | Should -BeTrue
        $result.Value | Should -BeNullOrEmpty
    }

    It 'writes a verbose record naming the FullyQualifiedErrorId, never the variable value, on an unexpected Get-Variable failure' {
        # Force every Get-Variable call to fail with an error id outside the
        # break-list (ScopeIsNotDefined/ArgumentOutOfRange/PSArgumentOutOfRange)
        # so the final catch's Write-Verbose path runs on every scope probed.
        Mock -CommandName Get-Variable {
            throw (New-Object System.Management.Automation.RuntimeException('secret-value-should-not-leak'))
        }

        $verboseOutput = Get-FsuCallerVariable -Name 'FsuAnyVariable' -Verbose 4>&1
        $verboseRecords = @($verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })

        $verboseRecords.Count | Should -BeGreaterThan 0
        ($verboseRecords | Out-String) | Should -Match 'FullyQualifiedErrorId'
        ($verboseRecords | Out-String) | Should -Not -Match 'secret-value-should-not-leak'
    }
}
