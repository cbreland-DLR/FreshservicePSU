[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Test', 'Analyze', 'Build', 'Validate', 'Clean')]
    [string[]]$Task = @('Test'),

    [switch]$Bootstrap,

    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Output')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleName = 'FreshservicePSU'
$moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath $moduleName
$manifestPath = Join-Path -Path $moduleRoot -ChildPath "$moduleName.psd1"
$analyzerSettingsPath = Join-Path -Path $PSScriptRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
$minimumVersions = @{
    Pester           = [version]'5.7.1'
    PSScriptAnalyzer = [version]'1.25.0'
}

function Import-BuildDependency {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $minimumVersion = $minimumVersions[$Name]
    $available = Get-Module -Name $Name -ListAvailable |
        Where-Object Version -GE $minimumVersion |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $available -and $Bootstrap) {
        $installCommand = Get-Command -Name Install-PSResource -ErrorAction SilentlyContinue
        if (-not $installCommand) {
            throw 'Install-PSResource is required to bootstrap build dependencies.'
        }

        Install-PSResource -Name $Name -Version $minimumVersion -Scope CurrentUser -TrustRepository
        $available = Get-Module -Name $Name -ListAvailable |
            Where-Object Version -GE $minimumVersion |
            Sort-Object Version -Descending |
            Select-Object -First 1
    }

    if (-not $available) {
        throw "$Name $minimumVersion or later is required. Re-run with -Bootstrap to install it."
    }

    Import-Module -Name $available.Path -Force
}

function Test-PowerShellSyntax {
    $parseErrors = foreach ($path in @($moduleRoot, (Join-Path $PSScriptRoot 'tests'), $PSCommandPath)) {
        $files = if (Test-Path -Path $path -PathType Leaf) {
            Get-Item -Path $path
        }
        else {
            Get-ChildItem -Path $path -Recurse -File |
                Where-Object Extension -In @('.ps1', '.psm1', '.psd1')
        }

        foreach ($file in $files) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName,
                [ref]$tokens,
                [ref]$errors
            )

            foreach ($parseError in $errors) {
                [PSCustomObject]@{
                    Path    = $file.FullName
                    Line    = $parseError.Extent.StartLineNumber
                    Message = $parseError.Message
                }
            }
        }
    }

    if ($parseErrors) {
        $parseErrors | Format-Table -Wrap | Out-Host
        throw "PowerShell parsing failed with $(@($parseErrors).Count) error(s)."
    }

    Write-Host 'PowerShell syntax: passed'
}

function Test-ModuleMetadata {
    $manifest = Test-ModuleManifest -Path $manifestPath
    if ($manifest.Name -ne $moduleName) {
        throw "Manifest name '$($manifest.Name)' does not match '$moduleName'."
    }

    Write-Host "Module manifest: passed ($moduleName $($manifest.Version))"
    $manifest
}

function Invoke-OfflineTests {
    Import-BuildDependency -Name Pester

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = @(
        Join-Path -Path $PSScriptRoot -ChildPath 'tests/Meta.tests.ps1'
        Join-Path -Path $PSScriptRoot -ChildPath 'tests/Manifest.tests.ps1'
        Join-Path -Path $PSScriptRoot -ChildPath 'tests/Help.tests.ps1'
    )
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Normal'
    $configuration.Filter.ExcludeTag = @('Network')

    $result = Invoke-Pester -Configuration $configuration
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
        throw "Offline tests failed with result '$($result.Result)' and $($result.FailedCount) test failure(s)."
    }
}

function Invoke-StaticAnalysis {
    Import-BuildDependency -Name PSScriptAnalyzer

    $diagnostics = foreach ($file in Get-ChildItem -Path $moduleRoot, (Join-Path $PSScriptRoot 'tests') -Recurse -File) {
        if ($file.Extension -in @('.ps1', '.psm1', '.psd1')) {
            try {
                Invoke-ScriptAnalyzer -Path $file.FullName -Settings $analyzerSettingsPath -ErrorAction Stop
            }
            catch {
                throw "PSScriptAnalyzer failed for '$($file.FullName)': $($_.Exception.Message)"
            }
        }
    }

    if ($diagnostics) {
        $diagnostics |
            Sort-Object Severity, ScriptPath, Line |
            Format-Table Severity, RuleName, ScriptName, Line, Message -Wrap |
            Out-Host
        throw "Static analysis failed with $(@($diagnostics).Count) finding(s)."
    }

    Write-Host 'Static analysis: passed'
}

function New-ModuleArtifact {
    $manifest = Test-ModuleMetadata
    $versionRoot = Join-Path -Path $OutputPath -ChildPath "$moduleName/$($manifest.Version)"

    if (Test-Path -Path $versionRoot) {
        Remove-Item -Path $versionRoot -Recurse -Force
    }

    New-Item -Path $versionRoot -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $moduleRoot '*') -Destination $versionRoot -Recurse -Force
    Test-ModuleManifest -Path (Join-Path $versionRoot "$moduleName.psd1") | Out-Null
    Write-Host "Build artifact: $versionRoot"
}

foreach ($taskName in $Task) {
    switch ($taskName) {
        'Test' {
            Test-PowerShellSyntax
            Test-ModuleMetadata | Out-Null
            Invoke-OfflineTests
        }
        'Analyze' {
            Test-PowerShellSyntax
            Invoke-StaticAnalysis
        }
        'Build' {
            Test-PowerShellSyntax
            New-ModuleArtifact
        }
        'Validate' {
            Test-PowerShellSyntax
            Test-ModuleMetadata | Out-Null
            Invoke-OfflineTests
            Invoke-StaticAnalysis
        }
        'Clean' {
            if (Test-Path -Path $OutputPath) {
                Remove-Item -Path $OutputPath -Recurse -Force
            }
            Write-Host "Cleaned: $OutputPath"
        }
    }
}
