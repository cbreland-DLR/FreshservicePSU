[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Test', 'Analyze', 'Format', 'Build', 'Validate', 'Clean')]
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
    Pester = [version]'5.7.1'
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
        } else {
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
                    Path = $file.FullName
                    Line = $parseError.Extent.StartLineNumber
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

    # tests/Integration is the credentialed lane and is intentionally never
    # discovered here. tests/Unit and tests/Contract may be empty while their
    # phases are unimplemented; Pester is configured to treat an empty
    # directory as "nothing to run" rather than a discovery failure.
    $testRoots = @('tests/Unit', 'tests/Contract', 'tests/Architecture') |
        ForEach-Object { Join-Path -Path $PSScriptRoot -ChildPath $_ } |
        Where-Object { (Get-ChildItem -Path $_ -Filter '*.Tests.ps1' -Recurse -File -ErrorAction SilentlyContinue) }

    $rootLevelSuites = @('tests/Manifest.tests.ps1', 'tests/Meta.tests.ps1', 'tests/Documentation.Tests.ps1') |
        ForEach-Object { Join-Path -Path $PSScriptRoot -ChildPath $_ } |
        Where-Object { Test-Path -Path $_ -PathType Leaf }

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = @($testRoots) + @($rootLevelSuites)
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Normal'
    $configuration.Filter.ExcludeTag = @('Network')

    # build.ps1's Set-StrictMode -Version Latest leaks by scope inheritance
    # into the scriptblocks Invoke-Pester executes. That is deliberate: tests
    # are held to the same strictness as module code, so an unguarded .Count
    # on a pipeline result that can yield $null fails here rather than in a
    # later phase.
    $result = Invoke-Pester -Configuration $configuration

    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
        throw "Offline tests failed with result '$($result.Result)' and $($result.FailedCount) test failure(s)."
    }
}

function Invoke-FormatCheck {
    Import-BuildDependency -Name PSScriptAnalyzer

    # A dedicated formatting settings hashtable, not
    # PSScriptAnalyzerSettings.psd1 (that file carries severity/rule
    # exclusions for Invoke-ScriptAnalyzer, and passing it to
    # Invoke-Formatter would replace rather than extend the built-in
    # formatting preset, silently disabling indentation/brace checks).
    #
    # Brace placement, indentation, and whitespace are all enforced. The whole
    # tree was normalized to this rule set in Phase 2 while it was still
    # essentially empty, which is the only cheap moment to adopt a formatting
    # standard. PSAlignAssignmentStatement is deliberately left out: aligned
    # assignment blocks are churn-prone and are not this repo's style.
    $formatterSettings = @{
        IncludeRules = @(
            'PSPlaceOpenBrace',
            'PSPlaceCloseBrace',
            'PSUseConsistentIndentation',
            'PSUseConsistentWhitespace'
        )
        Rules = @{
            PSPlaceOpenBrace = @{
                Enable = $true
                OnSameLine = $true
                NewLineAfter = $true
                IgnoreOneLineBlock = $true
            }
            PSPlaceCloseBrace = @{
                Enable = $true
                NewLineAfter = $false
                IgnoreOneLineBlock = $true
                NoEmptyLineBefore = $false
            }
            PSUseConsistentIndentation = @{
                Enable = $true
                Kind = 'space'
                IndentationSize = 4
            }
            PSUseConsistentWhitespace = @{
                Enable = $true
                CheckOpenBrace = $true
                CheckOpenParen = $true
                CheckOperator = $true
                CheckSeparator = $true
            }
        }
    }

    $drifted = foreach ($file in Get-ChildItem -Path $moduleRoot, (Join-Path $PSScriptRoot 'tests') -Recurse -File) {
        if ($file.Extension -notin @('.ps1', '.psm1')) {
            # .psd1 data files are excluded: PSUseConsistentIndentation has a
            # known quirk of wanting the top-level hashtable's closing brace
            # indented one level in, which does not match how this repo (and
            # PowerShell tooling generally) writes manifest/data files.
            continue
        }

        $original = Get-Content -LiteralPath $file.FullName -Raw
        if ([string]::IsNullOrEmpty($original)) {
            continue
        }

        $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $formatterSettings
        if ($formatted -ne $original) {
            $file.FullName
        }
    }

    if ($drifted) {
        $drifted | ForEach-Object { Write-Host "Format drift: $_" }
        throw "Formatting check failed for $(@($drifted).Count) file(s): $($drifted -join ', ')"
    }

    Write-Host 'Formatting: passed'
}

function Invoke-CleanImportCheck {
    # A fresh -NoProfile child process, not -Verbose: PowerShell itself emits
    # "Loading module from path ..." verbose lines on module load, which would
    # be indistinguishable from the module's own output if -Verbose were used
    # here. Only the module's own error/warning/information output is asserted.
    $tempScriptPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "fsu-clean-import-$([guid]::NewGuid()).ps1"
    try {
        @"
`$ErrorActionPreference = 'Stop'
`$manifestPath = '$manifestPath'
`$streamOutput = [System.Collections.Generic.List[string]]::new()
`$errorOutput = Import-Module -Name `$manifestPath -Force -ErrorAction Stop -WarningVariable warnings -InformationVariable information 2>&1 3>&1
foreach (`$item in `$errorOutput) { `$streamOutput.Add("Error: `$item") }
foreach (`$item in `$warnings) { `$streamOutput.Add("Warning: `$item") }
foreach (`$item in `$information) { `$streamOutput.Add("Information: `$item") }
`$commandCount = @(Get-Command -Module FreshservicePSU).Count
[PSCustomObject]@{ StreamOutput = `$streamOutput; CommandCount = `$commandCount } | ConvertTo-Json -Depth 5 -Compress
"@ | Set-Content -LiteralPath $tempScriptPath -Encoding utf8NoBOM

        $rawResult = & pwsh -NoProfile -NonInteractive -File $tempScriptPath
        if ($LASTEXITCODE -ne 0) {
            throw "Clean-import check child process exited with code $LASTEXITCODE. Output: $($rawResult -join [Environment]::NewLine)"
        }

        $result = ($rawResult -join [Environment]::NewLine) | ConvertFrom-Json
    } finally {
        Remove-Item -Path $tempScriptPath -Force -ErrorAction SilentlyContinue
    }

    if ($result.StreamOutput -and @($result.StreamOutput).Count -gt 0) {
        $result.StreamOutput | ForEach-Object { Write-Host $_ }
        throw "Clean import produced $(@($result.StreamOutput).Count) stream message(s); import must be silent."
    }

    if ($result.CommandCount -ne 0) {
        throw "Clean import exports $($result.CommandCount) command(s); expected 0 at this phase."
    }

    Write-Host 'Clean import: passed'
}

function Invoke-StaticAnalysis {
    Import-BuildDependency -Name PSScriptAnalyzer

    $diagnostics = foreach ($file in Get-ChildItem -Path $moduleRoot, (Join-Path $PSScriptRoot 'tests') -Recurse -File) {
        if ($file.Extension -in @('.ps1', '.psm1', '.psd1')) {
            try {
                Invoke-ScriptAnalyzer -Path $file.FullName -Settings $analyzerSettingsPath -ErrorAction Stop
            } catch {
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
        'Format' {
            Invoke-FormatCheck
        }
        'Build' {
            Test-PowerShellSyntax
            New-ModuleArtifact
        }
        'Validate' {
            Test-PowerShellSyntax
            Test-ModuleMetadata | Out-Null
            Invoke-CleanImportCheck
            Invoke-FormatCheck
            Invoke-StaticAnalysis
            Invoke-OfflineTests
        }
        'Clean' {
            if (Test-Path -Path $OutputPath) {
                Remove-Item -Path $OutputPath -Recurse -Force
            }
            Write-Host "Cleaned: $OutputPath"
        }
    }
}
