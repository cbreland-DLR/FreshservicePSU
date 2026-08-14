BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot

    function Get-DocumentedCommand {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$StartHeading,

            [Parameter()]
            [string]$EndHeading = '^## '
        )

        $inSection = $false
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -match $StartHeading) {
                $inSection = $true
                continue
            }

            if ($inSection -and $line -match $EndHeading) {
                break
            }

            if ($inSection -and $line -match '^\|(?: [^|]+ \|)? `(?<Command>(?:Add|Get|New|Search|Set)-FreshService[^` ]+)` \|') {
                $Matches.Command
            }
        }
    }

    $supportedCommands = @(
        Get-DocumentedCommand `
            -Path (Join-Path $repositoryRoot 'docs/SUPPORTED_COMMANDS.md') `
            -StartHeading '^## 1\. Ticket operations$' `
            -EndHeading '^## 5\. Contract shared by every command$'
    ) | Sort-Object -Unique

    $planCommands = @(
        Get-DocumentedCommand `
            -Path (Join-Path $repositoryRoot 'docs/IMPLEMENTATION_PLAN.md') `
            -StartHeading '^## 2\. Supported command set$'
    ) | Sort-Object -Unique

    $pruneCommands = @(
        Get-DocumentedCommand `
            -Path (Join-Path $repositoryRoot 'docs/COMMAND_PRUNE_LIST.md') `
            -StartHeading '^## 2\. Final supported commands$'
    ) | Sort-Object -Unique
}

Describe 'Authoritative documentation consistency' {
    It 'defines exactly 22 supported commands' {
        $supportedCommands.Count | Should -Be 22
    }

    It 'uses the same command inventory in the reference and plan' {
        Compare-Object $supportedCommands $planCommands | Should -BeNullOrEmpty
    }

    It 'uses the same command inventory in the reference and prune decision' {
        Compare-Object $supportedCommands $pruneCommands | Should -BeNullOrEmpty
    }

    It 'classifies every endpoint comparison row' {
        $rows = Import-Csv (Join-Path $repositoryRoot 'docs/FRESHSERVICE_API_V2_ENDPOINT_COMPARISON.csv')

        $rows.Count | Should -BeGreaterThan 0
        foreach ($row in $rows) {
            $row.'Decision (Add/Skip)' | Should -Match '^(Add|Skip|Conditional) - '
        }
    }

    It 'uses unique active open-question identifiers' {
        $questionIds = Get-Content (Join-Path $repositoryRoot 'docs/OPEN_QUESTIONS.md') |
            Where-Object { $_ -match '^\| Q(?<Number>\d+) \|' } |
            ForEach-Object { [int]$Matches.Number }

        $questionIds.Count | Should -BeGreaterThan 0
        ($questionIds | Sort-Object -Unique).Count | Should -Be $questionIds.Count
    }

    It 'lists every active open question in the blocking map' {
        $content = Get-Content (Join-Path $repositoryRoot 'docs/OPEN_QUESTIONS.md')
        $blockingIds = $content |
            Where-Object { $_ -match '^\| \*\*(?<Id>Q\d+)\*\* \|' } |
            ForEach-Object { $Matches.Id } |
            Sort-Object -Unique
        $detailIds = $content |
            Where-Object { $_ -match '^\| (?<Id>Q\d+) \|' } |
            ForEach-Object { $Matches.Id } |
            Sort-Object -Unique

        Compare-Object $blockingIds $detailIds | Should -BeNullOrEmpty
    }

    It 'uses the same verified legacy command count in evidence documents' {
        $documentsAndPatterns = @{
            'docs/API_V2_COVERAGE_MATRIX.md' = 'contains (?<Count>\d+) public functions'
            'docs/CURRENT_STATE_REVIEW.md' = 'Public command files/functions \| (?<Count>\d+)'
            'docs/COMMAND_PRUNE_LIST.md' = 'module has (?<Count>\d+) legacy public commands'
        }

        $counts = @(foreach ($entry in $documentsAndPatterns.GetEnumerator()) {
                $content = Get-Content (Join-Path $repositoryRoot $entry.Key) -Raw
                $content | Should -Match $entry.Value
                [int]([regex]::Match($content, $entry.Value).Groups['Count'].Value)
            })

        @($counts | Sort-Object -Unique).Count | Should -Be 1
        $counts[0] | Should -Be 165
    }

    It 'has no broken relative Markdown links' {
        $markdownFiles = Get-ChildItem -Path $repositoryRoot -Filter '*.md' -File -Recurse |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }

        $brokenLinks = foreach ($file in $markdownFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($match in [regex]::Matches($content, '\[[^\]]*\]\((?<Target>[^)]+)\)')) {
                $target = $match.Groups['Target'].Value
                if ($target -match '^(?:[a-z][a-z0-9+.-]*:|#)') {
                    continue
                }

                $relativePath = ($target -split '#', 2)[0]
                if ($relativePath -and -not (Test-Path -LiteralPath (Join-Path $file.DirectoryName $relativePath))) {
                    '{0}: {1}' -f $file.FullName, $target
                }
            }
        }

        $brokenLinks | Should -BeNullOrEmpty
    }

    It 'marks the checked-in implementation as transitional' {
        $readme = Get-Content (Join-Path $repositoryRoot 'README.md') -Raw
        $readme | Should -Match 'transition stage'
        $readme | Should -Match 'does not yet implement the target architecture'
    }

    It 'references only open-question identifiers that exist' {
        $registryPath = Join-Path $repositoryRoot 'docs/OPEN_QUESTIONS.md'

        $definedIds = Get-Content $registryPath |
            Where-Object { $_ -match '^\| (?<Id>Q\d+) \|' } |
            ForEach-Object { $Matches.Id }

        $citingDocuments = @(
            'docs/ARCHITECTURE.md'
            'docs/IMPLEMENTATION_PLAN.md'
            'docs/SUPPORTED_COMMANDS.md'
        )

        foreach ($document in $citingDocuments) {
            $referencedIds = Get-Content (Join-Path $repositoryRoot $document) |
                Select-String -Pattern '\bQ\d+\b' -AllMatches |
                ForEach-Object { $_.Matches.Value } |
                Sort-Object -Unique

            foreach ($id in $referencedIds) {
                $definedIds | Should -Contain $id -Because "$document cites $id, which must exist in OPEN_QUESTIONS.md"
            }
        }
    }

    It 'does not define module-level PSU roles' {
        $authoritativeDocuments = @(
            'README.md'
            'docs/ARCHITECTURE.md'
            'docs/IMPLEMENTATION_PLAN.md'
            'docs/OPEN_QUESTIONS.md'
            'docs/SUPPORTED_COMMANDS.md'
        )

        foreach ($document in $authoritativeDocuments) {
            Get-Content (Join-Path $repositoryRoot $document) -Raw |
                Should -Not -Match 'FreshservicePSU\.(?:Read|Write)'
        }
    }
}
