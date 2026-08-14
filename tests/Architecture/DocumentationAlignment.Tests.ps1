<#
.SYNOPSIS
    Documentation-alignment checks ported from the retired
    scripts/Test-Phase0Alignment.ps1, plus the Phase 2 docs/en-US <->
    manifest cross-check from IMPLEMENTATION_PLAN.md §6.

.DESCRIPTION
    Verifies:
      (a) SUPPORTED_COMMANDS.md lists exactly 22 distinct command names;
      (b) other authoritative documents that state a command count all say
          22, and none reference a stale count;
      (c) IMPLEMENTATION_PLAN.md's command table matches the 22-command set
          exactly (an empty match set is a failure, not a vacuous pass);
      (d) COMMAND_PRUNE_LIST.md's "Final supported commands" section covers
          the same 22 names;
      (e) the endpoint-comparison CSV carries an explicit Add/Skip/Conditional
          decision on every row;
      (f) no accepted document claims external asset synchronization is
          in scope (word-boundary-anchored negation check);
      (g) the set of docs/en-US/*.md basenames equals the set of manifest
          FunctionsToExport exactly, once either is non-empty.
#>

BeforeDiscovery {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
    $script:docsRoot = Join-Path $repoRoot 'docs'

    $supportedCommandsPath = Join-Path $docsRoot 'SUPPORTED_COMMANDS.md'
    $script:commandNames = @()
    if (Test-Path -LiteralPath $supportedCommandsPath) {
        $supportedCommandsContent = Get-Content -LiteralPath $supportedCommandsPath -Raw
        $commandPattern = '(?m)^\|\s*`((?:Get|Set|New|Add|Remove|Search|Restore|Invoke)-FreshService[A-Za-z]+)`\s*\|'
        $script:commandNames = [regex]::Matches($supportedCommandsContent, $commandPattern) |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    }

    $script:docsToCheckForCount = @(
        (Join-Path $docsRoot 'IMPLEMENTATION_PLAN.md'),
        (Join-Path $docsRoot 'ARCHITECTURE.md'),
        (Join-Path $repoRoot 'CLAUDE.md'),
        (Join-Path $repoRoot 'README.md')
    )

    # Per-document, per-match test cases for the stale-count check.
    # Hashtables (not PSCustomObject) are used because Pester's -ForEach
    # binds hashtable keys directly to test-scoped variables.
    $script:staleCountCases = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($path in $script:docsToCheckForCount) {
        if (-not (Test-Path -LiteralPath $path)) {
            $script:staleCountCases.Add(@{ Path = $path; Missing = $true; Number = $null })
            continue
        }
        $text = Get-Content -LiteralPath $path -Raw
        $staleCountPattern = '(?i)\b(\d+)-command\b'
        $countMatches = [regex]::Matches($text, $staleCountPattern)
        foreach ($m in $countMatches) {
            $script:staleCountCases.Add(@{ Path = $path; Missing = $false; Number = [int]$m.Groups[1].Value })
        }
    }

    # --- synchronization negation windows (word-boundary anchored) --------
    $script:acceptedDocs = @(
        (Join-Path $docsRoot 'ARCHITECTURE.md'),
        (Join-Path $docsRoot 'SUPPORTED_COMMANDS.md'),
        (Join-Path $docsRoot 'IMPLEMENTATION_PLAN.md'),
        (Join-Path $repoRoot 'CLAUDE.md'),
        (Join-Path $repoRoot 'README.md')
    )
    $script:syncNegationPattern = '(?i)\b(no|not|without|excludes?|out of scope|is not part of|does\s+not\s+implement|remains?\s+out\s+of\s+scope|doesn''t|does not)\b'
    $script:syncCases = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($path in $script:acceptedDocs) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $docText = (Get-Content -LiteralPath $path -Raw) -replace '\s+', ' '
        $syncMatches = [regex]::Matches($docText, '(?i)synchroniz\w*')
        foreach ($m in $syncMatches) {
            $start = [Math]::Max(0, $m.Index - 100)
            $len = [Math]::Min(160, $docText.Length - $start)
            $window = $docText.Substring($start, $len)
            $script:syncCases.Add(@{ Path = $path; Window = $window; HasNegation = ($window -match $script:syncNegationPattern) })
        }
    }

    # --- docs/en-US <-> manifest FunctionsToExport (Phase 2) --------------
    $script:enUsRoot = Join-Path $docsRoot 'en-US'
    $script:manifestPathForDocs = Join-Path $repoRoot 'FreshservicePSU/FreshservicePSU.psd1'
    $manifestRawForDocs = Import-PowerShellDataFile -Path $script:manifestPathForDocs
    $script:exportedNames = @($manifestRawForDocs.FunctionsToExport) | Sort-Object -Unique

    $script:topicNames = @()
    $script:enUsRootExists = Test-Path -LiteralPath $script:enUsRoot
    if ($script:enUsRootExists) {
        $script:topicNames = Get-ChildItem -LiteralPath $script:enUsRoot -Filter '*.md' -File -ErrorAction SilentlyContinue |
            ForEach-Object { $_.BaseName } | Sort-Object -Unique
    }
}

Describe 'SUPPORTED_COMMANDS.md is the 22-command authority' {

    It 'lists exactly 22 distinct command names' {
        $commandNames.Count | Should -Be 22 -Because "found: $($commandNames -join ', ')"
    }
}

Describe 'Authoritative documents carry no stale command count' {

    Context 'Document exists' -ForEach $staleCountCases {
        It "<Path> exists" {
            $Missing | Should -Be $false
        }
    }

    Context 'Every N-command reference says 22' -ForEach ($staleCountCases | Where-Object { -not $_.Missing }) {
        It "<Path> '<Number>-command' reference equals 22" {
            $Number | Should -Be 22
        }
    }
}

Describe 'IMPLEMENTATION_PLAN.md command table matches SUPPORTED_COMMANDS.md exactly' {

    BeforeAll {
        $planPath = Join-Path $docsRoot 'IMPLEMENTATION_PLAN.md'
        $planText = Get-Content -LiteralPath $planPath -Raw
        $planMatches = [regex]::Matches($planText, '(?m)^\|\s*[A-Za-z /]+\s*\|\s*`((?:Get|Set|New|Add|Remove|Search|Restore|Invoke)-FreshService[A-Za-z]+)`\s*\|')
        $planNames = $planMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    }

    It 'extracts a non-empty command set from the plan (an empty match set is a failure, not a vacuous pass)' {
        $planNames.Count | Should -BeGreaterThan 0 -Because 'a broken extraction regex must fail loudly, not be skipped'
    }

    It 'contains every SUPPORTED_COMMANDS.md name' {
        $missingFromPlan = Compare-Object -ReferenceObject $commandNames -DifferenceObject $planNames |
            Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject }
        $missingFromPlan | Should -BeNullOrEmpty -Because "IMPLEMENTATION_PLAN.md command table is missing: $($missingFromPlan -join ', ')"
    }

    It 'contains no name outside SUPPORTED_COMMANDS.md' {
        $extraInPlan = Compare-Object -ReferenceObject $commandNames -DifferenceObject $planNames |
            Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { $_.InputObject }
        $extraInPlan | Should -BeNullOrEmpty -Because "IMPLEMENTATION_PLAN.md command table lists names not in SUPPORTED_COMMANDS.md: $($extraInPlan -join ', ')"
    }
}

Describe 'COMMAND_PRUNE_LIST.md final-supported-commands section matches SUPPORTED_COMMANDS.md' {

    BeforeAll {
        $prunePath = Join-Path $docsRoot 'COMMAND_PRUNE_LIST.md'
        $pruneText = Get-Content -LiteralPath $prunePath -Raw
        $pruneCommandPattern = '(?:Get|Set|New|Add|Remove|Search|Restore|Invoke)-FreshService[A-Za-z]+'
        $section2Match = [regex]::Match($pruneText, '(?s)## 2\. Final supported commands(.*?)\n## 3\.')
    }

    It 'has a "## 2. Final supported commands" section' {
        $section2Match.Success | Should -Be $true
    }

    It 'covers every SUPPORTED_COMMANDS.md name' {
        $pruneNames = [regex]::Matches($section2Match.Groups[1].Value, $pruneCommandPattern) |
            ForEach-Object { $_.Value } | Sort-Object -Unique
        $missingFromPrune = Compare-Object -ReferenceObject $commandNames -DifferenceObject $pruneNames |
            Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject }
        $missingFromPrune | Should -BeNullOrEmpty -Because "COMMAND_PRUNE_LIST.md 'Final supported commands' section is missing: $($missingFromPrune -join ', ')"
    }
}

Describe 'Endpoint-comparison CSV carries an explicit decision on every row' {

    BeforeAll {
        $csvPath = Join-Path $docsRoot 'FRESHSERVICE_API_V2_ENDPOINT_COMPARISON.csv'
        $rows = Import-Csv -LiteralPath $csvPath
        $decisionColumn = 'Decision (Add/Skip)'
    }

    It 'has at least one data row' {
        $rows.Count | Should -BeGreaterThan 0
    }

    It 'has no row with an empty decision' {
        $blankDecisionRows = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.$decisionColumn) })
        $families = ($blankDecisionRows | ForEach-Object { $_.'Endpoint family' }) -join ', '
        $blankDecisionRows.Count | Should -Be 0 -Because "rows with empty decision: $families"
    }

    It 'has no row whose decision is not Add/Skip/Conditional' {
        $validPrefixes = @('Add', 'Skip', 'Conditional')
        $badDecisionRows = @($rows | Where-Object {
                $decision = $_.$decisionColumn
                -not [string]::IsNullOrWhiteSpace($decision) -and
                -not @($validPrefixes | Where-Object { $decision.TrimStart() -like "$_*" })
            })
        $families = ($badDecisionRows | ForEach-Object { $_.'Endpoint family' }) -join ', '
        $badDecisionRows.Count | Should -Be 0 -Because "rows with invalid decision: $families"
    }
}

Describe 'No accepted document claims external asset synchronization is in scope' {

    Context 'Every synchronization mention has a nearby negation' -ForEach $syncCases {
        It "<Path> mention '<Window>' is negated" {
            $HasNegation | Should -Be $true -Because "mentions synchronization without an explicit, word-boundary-anchored negation nearby: ...$Window..."
        }
    }
}

Describe 'docs/en-US topics match manifest FunctionsToExport exactly (IMPLEMENTATION_PLAN.md §6, Phase 2)' {

    # Both directions are correct when either set is empty: a missing en-US
    # directory yields no topics, and an empty export list yields no commands,
    # so the two comparisons pass without needing a skip.
    It 'has no orphan docs/en-US topic (a topic with no matching exported command)' {
        $orphans = $topicNames | Where-Object { $_ -notin $exportedNames }
        $orphans | Should -BeNullOrEmpty -Because "orphan docs/en-US topics: $($orphans -join ', ')"
    }

    It 'has no undocumented exported command (an export with no docs/en-US topic)' {
        $undocumented = $exportedNames | Where-Object { $_ -notin $topicNames }
        $undocumented | Should -BeNullOrEmpty -Because "exported commands with no docs/en-US topic: $($undocumented -join ', ')"
    }
}
