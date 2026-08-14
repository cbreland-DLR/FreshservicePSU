<#
.SYNOPSIS
    Rejects forbidden runtime targets, APIs, and process-global state under
    FreshservicePSU/, per ARCHITECTURE.md §12/§13 and IMPLEMENTATION_PLAN.md
    Phase 2.
#>

BeforeDiscovery {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
    $script:moduleRoot = Join-Path $repoRoot 'FreshservicePSU'
    $script:manifestPath = Join-Path $moduleRoot 'FreshservicePSU.psd1'
    $script:publicRoot = Join-Path $moduleRoot 'Public'

    function Get-AstForFile {
        param([string]$Path)
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
        @{ Ast = $ast; Tokens = $tokens; ParseErrors = $parseErrors }
    }

    $script:sourceFiles = @()
    if (Test-Path -LiteralPath $moduleRoot) {
        $script:sourceFiles = Get-ChildItem -LiteralPath $moduleRoot -Recurse -File -Include '*.ps1', '*.psm1' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName }
    }

    # Direct transport is confined to Private/Http (ARCHITECTURE.md §11): every
    # module file outside that one directory is checked, not just Public/. A
    # helper under Private/Execution or Private/Configuration calling
    # Invoke-RestMethod would bypass the shared pipeline just as surely as a
    # public command doing it.
    $script:httpImplementationRoot = Join-Path (Join-Path $moduleRoot 'Private') 'Http'
    $script:nonTransportFiles = @(
        $script:sourceFiles | Where-Object {
            -not $_.StartsWith($script:httpImplementationRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::Ordinal)
        }
    )

    # --- CommandAst-detected forbidden HTTP calls outside Private/Http ----
    $script:publicHttpViolations = [System.Collections.Generic.List[hashtable]]::new()
    $forbiddenHttpCommands = @('Invoke-RestMethod', 'Invoke-WebRequest')
    foreach ($file in $script:nonTransportFiles) {
        $parsed = Get-AstForFile -Path $file
        if (-not $parsed.Ast) { continue }
        $commandAsts = $parsed.Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($cmd in $commandAsts) {
            $cmdName = $cmd.GetCommandName()
            if ($cmdName -in $forbiddenHttpCommands) {
                $script:publicHttpViolations.Add(@{ File = $file; Command = $cmdName; Line = $cmd.Extent.StartLineNumber })
            }
        }
        # HttpClient used directly (New-Object System.Net.Http.HttpClient, [System.Net.Http.HttpClient]::new(), etc.)
        $typeExpressionAsts = $parsed.Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.TypeExpressionAst] }, $true)
        foreach ($t in $typeExpressionAsts) {
            if ($t.TypeName.FullName -match 'HttpClient') {
                $script:publicHttpViolations.Add(@{ File = $file; Command = "[$($t.TypeName.FullName)]"; Line = $t.Extent.StartLineNumber })
            }
        }
        $newObjectAsts = $commandAsts | Where-Object { $_.GetCommandName() -eq 'New-Object' }
        foreach ($n in $newObjectAsts) {
            if ($n.Extent.Text -match 'HttpClient') {
                $script:publicHttpViolations.Add(@{ File = $file; Command = 'New-Object HttpClient'; Line = $n.Extent.StartLineNumber })
            }
        }
    }

    # --- CommandAst-detected UseBasicParsing / ServicePointManager / System.Web ---
    $script:apiTextViolations = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($file in $script:sourceFiles) {
        $raw = Get-Content -LiteralPath $file -Raw -ErrorAction SilentlyContinue
        if ($null -eq $raw) { continue }
        if ($raw -match 'UseBasicParsing') {
            $script:apiTextViolations.Add(@{ File = $file; Pattern = 'UseBasicParsing' })
        }
        if ($raw -match 'ServicePointManager') {
            $script:apiTextViolations.Add(@{ File = $file; Pattern = 'ServicePointManager' })
        }
        if ($raw -match 'System\.Web') {
            $script:apiTextViolations.Add(@{ File = $file; Pattern = 'System.Web' })
        }
    }

    # --- Global/Script-scoped credential/context/connection state ---------
    $script:globalStateViolations = [System.Collections.Generic.List[hashtable]]::new()
    $stateNamePattern = '(?i)(credential|context|connection|token|secret|apikey|api_key)'
    foreach ($file in $script:sourceFiles) {
        $parsed = Get-AstForFile -Path $file
        if (-not $parsed.Ast) { continue }
        $varAsts = $parsed.Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
        foreach ($v in $varAsts) {
            if ($v.VariablePath.IsGlobal -or ($v.VariablePath.DriveName -eq 'Script')) {
                if ($v.VariablePath.UserPath -match $stateNamePattern) {
                    $script:globalStateViolations.Add(@{ File = $file; Variable = $v.Extent.Text; Line = $v.Extent.StartLineNumber })
                }
            }
        }
    }
}

Describe 'Runtime target (ARCHITECTURE.md §12, IMPLEMENTATION_PLAN.md Phase 2)' {

    BeforeAll {
        # Strip full-line and trailing '#' comments before scanning for a live
        # 'Desktop' reference, since the stock manifest template carries
        # commented-out boilerplate ("...valid for the PowerShell Desktop
        # edition only.") that is not an active edition reference.
        $manifestLines = Get-Content -LiteralPath $manifestPath |
            ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
            Where-Object { $_ }
        $manifestActiveText = $manifestLines -join "`n"
        $manifestRaw = Import-PowerShellDataFile -Path $manifestPath
    }

    It 'Manifest does not reference the Desktop PSEdition outside comments' {
        $manifestActiveText | Should -Not -Match 'Desktop'
    }

    It 'Manifest CompatiblePSEditions is exactly @(''Core'')' {
        @($manifestRaw.CompatiblePSEditions) | Should -Be @('Core')
    }

    It 'Manifest PowerShellVersion is at least 7.6' {
        [version]$manifestRaw.PowerShellVersion | Should -BeGreaterOrEqual ([version]'7.6')
    }
}

Describe 'Forbidden legacy HTTP/parsing APIs (ARCHITECTURE.md §11/§12)' {

    Context 'No file under FreshservicePSU/ uses UseBasicParsing, ServicePointManager, or System.Web' -ForEach $apiTextViolations {
        It "<File> does not reference '<Pattern>'" {
            $false | Should -Be $true -Because "found forbidden reference '$Pattern' in $File"
        }
    }

    It 'reports zero violations when none are planted' -Skip:($apiTextViolations.Count -gt 0) {
        $apiTextViolations.Count | Should -Be 0
    }
}

Describe 'Direct HTTP execution confined to Private/Http (ARCHITECTURE.md §11)' {

    Context 'No file outside Private/Http calls Invoke-RestMethod, Invoke-WebRequest, or HttpClient directly' -ForEach $publicHttpViolations {
        It "<File>:<Line> does not call '<Command>'" {
            $false | Should -Be $true -Because "found forbidden call '$Command' at $($File):$Line"
        }
    }

    It 'reports zero direct-transport calls outside Private/Http' {
        $publicHttpViolations.Count | Should -Be 0
    }
}

Describe 'No process-global credential/context/connection state (ARCHITECTURE.md §13)' {

    Context 'No Global: or Script: scoped credential/context/connection variable' -ForEach $globalStateViolations {
        It "<File>:<Line> does not define '<Variable>' at Global/Script scope" {
            $false | Should -Be $true -Because "found process-global state '$Variable' at $($File):$Line"
        }
    }

    It 'reports zero violations when none are planted' -Skip:($globalStateViolations.Count -gt 0) {
        $globalStateViolations.Count | Should -Be 0
    }
}
