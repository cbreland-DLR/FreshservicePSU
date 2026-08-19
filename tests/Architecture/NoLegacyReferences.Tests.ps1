<#
.SYNOPSIS
    Repository-wide scan for legacy connection-architecture references and
    removed command names: no file outside the explicit exclusion list below
    references a removed command name.

.DESCRIPTION
    Excluded from the scan, because they legitimately record legacy/removed
    surface as history or design record rather than as live documentation:
      - .git/                                (VCS internals)
      - docs/COMMAND_PRUNE_LIST.md            (explicit exclusion; the removal record itself)
      - docs/API_V2_COVERAGE_MATRIX.md        (explicit exclusion; legacy endpoint inventory)
      - CHANGELOG.md                          (project history; pre-fork entries)
      - docs/ARCHITECTURE.md                  (names Invoke-FreshworksRestMethod as the
                                                thing §11's pipeline replaces)
      - docs/FRESHSERVICE_API_V2_ENDPOINT_COMPARISON.csv
                                               (legacy endpoint-to-command inventory, same
                                                category as API_V2_COVERAGE_MATRIX.md)
      - CLAUDE.md                             (names the removed onboarding commands as an
                                                explicit, permanent scope-exclusion example)
      - .remember/                            (gitignored local session scratch, not repo
                                                content; git check-ignore confirms)
      - this test file itself                 (has to name the strings it looks for)
#>

BeforeDiscovery {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
    $script:docsRoot = Join-Path $repoRoot 'docs'
    $script:thisFile = $PSCommandPath

    $script:excludedFiles = @(
        (Join-Path $docsRoot 'COMMAND_PRUNE_LIST.md'),
        (Join-Path $docsRoot 'API_V2_COVERAGE_MATRIX.md'),
        (Join-Path $repoRoot 'CHANGELOG.md'),
        (Join-Path $docsRoot 'ARCHITECTURE.md'),
        (Join-Path $docsRoot 'FRESHSERVICE_API_V2_ENDPOINT_COMPARISON.csv'),
        (Join-Path $repoRoot 'CLAUDE.md'),
        $script:thisFile
    ) | ForEach-Object { (Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue).FullName } | Where-Object { $_ }

    # --- Fixed legacy connection surface -----------------------------------
    $script:legacyConnectionNames = @(
        'Invoke-FreshworksRestMethod',
        'Connect-Freshservice',
        'New-FreshServiceConnection',
        'FreshservicePSU.config'
    )

    # --- Removed command names, derived from COMMAND_PRUNE_LIST.md §4 -----
    $script:removedCommandNames = @()
    $prunePath = Join-Path $docsRoot 'COMMAND_PRUNE_LIST.md'
    if (Test-Path -LiteralPath $prunePath) {
        $pruneText = Get-Content -LiteralPath $prunePath -Raw
        $section4Match = [regex]::Match($pruneText, '(?s)## 4\. Removed legacy commands(.*?)\n## 5\.')
        if ($section4Match.Success) {
            $script:removedCommandNames = [regex]::Matches($section4Match.Groups[1].Value, '(?:Get|Set|New|Add|Remove|Search|Restore|Invoke)-FreshService[A-Za-z]+') |
                ForEach-Object { $_.Value } | Sort-Object -Unique
        }
    }

    # Confirm derivation actually found something — an empty set here means
    # the section-4 regex broke, not that nothing was removed.
    $script:removedCommandNamesFound = $script:removedCommandNames.Count -gt 0

    $script:allScanTerms = @($script:legacyConnectionNames) + @($script:removedCommandNames)

    # --- Enumerate all repo files (excluding .git/ and the exclusion list) ---
    $script:candidateFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '(^|[\\/])\.git($|[\\/])' -and $_.FullName -notmatch '(^|[\\/])\.remember($|[\\/])' } |
        Where-Object { $_.FullName -notin $script:excludedFiles } |
        ForEach-Object { $_.FullName }

    # Build one test case per (file, term) hit so each offending reference is
    # its own test.
    $script:violationCases = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($file in $script:candidateFiles) {
        $bytes = $null
        try {
            $content = Get-Content -LiteralPath $file -Raw -ErrorAction Stop
        } catch {
            continue
        }
        if ($null -eq $content) { continue }
        foreach ($term in $script:allScanTerms) {
            if ($content -match [regex]::Escape($term)) {
                $script:violationCases.Add(@{ File = $file; Term = $term })
            }
        }
    }
}

Describe 'Removed-command-name derivation is not vacuous' {

    It 'derives at least one removed command name from COMMAND_PRUNE_LIST.md §4' {
        $removedCommandNamesFound | Should -Be $true -Because 'an empty derived set means the section-4 extraction regex is broken, not that nothing was removed'
    }
}

Describe 'No legacy connection architecture or removed command reference remains' {

    Context 'Scanned file does not reference a legacy/removed name' -ForEach $(if (@($violationCases).Count) { $violationCases } else { @(@{ File = ''; Term = ''; EmptyForEach = $true }) }) {
        It "<File> does not reference '<Term>'" -Skip:([bool](Get-Variable -Name EmptyForEach -ValueOnly -ErrorAction SilentlyContinue)) {
            $false | Should -Be $true -Because "found legacy/removed reference '$Term' in $File"
        }
    }

    It 'reports zero violations when none are planted' -Skip:($violationCases.Count -gt 0) {
        $violationCases.Count | Should -Be 0
    }
}
