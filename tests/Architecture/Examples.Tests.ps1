<#
.SYNOPSIS
    Phase 7 example-script checks: public surface only, every command
    exercised, streaming discard, and mutation previews use -WhatIf.
#>

BeforeDiscovery {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
    $script:examplesRoot = Join-Path $repoRoot 'examples'
    $script:manifestPath = Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1'
    $script:exampleFiles = @()
    if (Test-Path -LiteralPath $examplesRoot) {
        $script:exampleFiles = @(Get-ChildItem -LiteralPath $examplesRoot -Filter '*.ps1' -File)
    }

    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $script:exportedNames = @($manifest.FunctionsToExport)
}

Describe 'Phase 7 examples exist and parse' {
    It 'has example scripts' {
        $exampleFiles.Count | Should -BeGreaterThan 0
    }

    It '<Name> parses without errors' -ForEach $(
        if ($exampleFiles.Count -eq 0) {
            @(@{ Name = 'missing'; Path = $examplesRoot; Missing = $true })
        } else {
            $exampleFiles | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName; Missing = $false } }
        }
    ) {
        $Missing | Should -BeFalse
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }
}

Describe 'Phase 7 examples stay on the public surface' {
    It 'does not call a private Fsu function' {
        $violations = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $exampleFiles) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            if ($text -match '(?i)\b[A-Z][A-Za-z]*-Fsu[A-Z]') {
                $violations.Add($file.Name)
            }
        }
        $violations | Should -BeNullOrEmpty
    }

    It 'does not expose tenant, stage, or secret parameters' {
        $violations = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $exampleFiles) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            if ($text -match '(?im)^\s*\[.*\]\s*\$(Tenant|Stage|BaseUri|ApiKey|Secret|WorkspaceId)\b') {
                $violations.Add($file.Name)
            }
        }
        $violations | Should -BeNullOrEmpty
    }

    It 'exercises every exported command' {
        $allText = ($exampleFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        $missing = @(
            $exportedNames | Where-Object { $allText -notmatch [regex]::Escape($_) }
        )
        $missing | Should -BeNullOrEmpty
    }
}

Describe 'Phase 7 example safety patterns' {
    It 'list examples discard PartialResults before treating a run as complete' {
        $listFiles = @(
            $exampleFiles | Where-Object { $_.Name -like 'Read-*.ps1' -or $_.Name -eq 'Complete-BoundedQuery.ps1' }
        )
        $listFiles.Count | Should -BeGreaterThan 0
        $helper = Get-Content -LiteralPath (Join-Path $examplesRoot 'Complete-BoundedQuery.ps1') -Raw
        $helper | Should -Match 'PartialResults'
        $helper | Should -Match 'Clear\('
    }

    It 'mutation previews use -WhatIf' {
        $previewFiles = @(
            $exampleFiles | Where-Object { $_.Name -like 'Preview-*.ps1' }
        )
        $previewFiles.Count | Should -BeGreaterThan 0
        foreach ($file in $previewFiles) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should -Match '-WhatIf'
            $text | Should -Not -Match '(?m)^\s*(New|Set|Add|Remove)-FreshService\w+\b(?!.*-WhatIf).*$'
        }
    }
}
