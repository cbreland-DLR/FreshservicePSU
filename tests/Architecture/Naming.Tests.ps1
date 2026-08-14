<#
.SYNOPSIS
    Enforces the naming boundary between Public/ and Private/ from
    ARCHITECTURE.md §12 and the manifest export shape from §12/§13.
#>

BeforeDiscovery {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
    $script:moduleRoot = Join-Path $repoRoot 'FreshservicePSU'
    $script:privateRoot = Join-Path $moduleRoot 'Private'
    $script:publicRoot = Join-Path $moduleRoot 'Public'
    $script:manifestPath = Join-Path $moduleRoot 'FreshservicePSU.psd1'
    $script:supportedDocPath = Join-Path $repoRoot 'docs/SUPPORTED_COMMANDS.md'

    function Get-FunctionDefinitionsUnder {
        param([string]$Path)

        $results = [System.Collections.Generic.List[hashtable]]::new()
        if (-not (Test-Path -LiteralPath $Path)) {
            return $results
        }

        $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Include '*.ps1', '*.psm1' -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors -and $parseErrors.Count -gt 0) {
                $results.Add(@{ File = $file.FullName; Name = "<parse error: $($parseErrors[0].Message)>" })
                continue
            }
            $functionAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($fn in $functionAsts) {
                $results.Add(@{ File = $file.FullName; Name = $fn.Name })
            }
        }
        return $results
    }

    $script:privateFunctions = Get-FunctionDefinitionsUnder -Path $privateRoot
    $script:publicFunctions = Get-FunctionDefinitionsUnder -Path $publicRoot

    $script:supportedCommandNames = @()
    if (Test-Path -LiteralPath $supportedDocPath) {
        $supportedText = Get-Content -LiteralPath $supportedDocPath -Raw
        $pattern = '(?<=`)(?:Get|Set|New|Add|Remove|Search|Restore|Invoke)-FreshService[A-Za-z]+(?=`)'
        $script:supportedCommandNames = [regex]::Matches($supportedText, $pattern) |
            ForEach-Object { $_.Value } | Sort-Object -Unique
    }
}

Describe 'Private helper naming (ARCHITECTURE.md §12)' {

    Context 'Every function defined under Private/ matches the Fsu pattern' -ForEach $privateFunctions {
        # Case-SENSITIVE, and the verb may be multiword: Phase 4 requires
        # ConvertTo-FsuRequestBody and ConvertFrom-FsuResponse
        # (ARCHITECTURE.md §11), which a `[a-z]+` verb cannot express. A
        # case-insensitive -Match would also wave through 'Get-fsuthing'.
        It "'<Name>' in <File> matches '^[A-Z][a-zA-Z]*-Fsu[A-Z]'" {
            $Name | Should -CMatch '^[A-Z][a-zA-Z]*-Fsu[A-Z]'
        }
    }

    Context 'No Private/ function name contains FreshService' -ForEach $privateFunctions {
        It "'<Name>' in <File> does not contain 'FreshService'" {
            $Name | Should -Not -Match 'FreshService'
        }
    }
}

Describe 'Public command naming (ARCHITECTURE.md §12)' {

    Context 'No Public/ function name contains Fsu' -ForEach $publicFunctions {
        It "'<Name>' in <File> does not contain 'Fsu'" {
            $Name | Should -Not -Match 'Fsu'
        }
    }
}

Describe 'Manifest export shape (ARCHITECTURE.md §12)' {

    BeforeAll {
        $manifestData = Test-ModuleManifest -Path $manifestPath -Verbose:$false -ErrorAction Stop -WarningAction SilentlyContinue
        $manifestRaw = Import-PowerShellDataFile -Path $manifestPath
    }

    It 'AliasesToExport is an empty array' {
        @($manifestRaw.AliasesToExport).Count | Should -Be 0
    }

    It 'VariablesToExport is an empty array' {
        @($manifestRaw.VariablesToExport).Count | Should -Be 0
    }

    It 'CmdletsToExport is an empty array' {
        @($manifestRaw.CmdletsToExport).Count | Should -Be 0
    }

    It 'FunctionsToExport is a subset of the 22-command SUPPORTED_COMMANDS.md inventory' {
        $exported = @($manifestRaw.FunctionsToExport)
        $unexpected = $exported | Where-Object { $_ -notin $supportedCommandNames }
        $unexpected | Should -BeNullOrEmpty -Because "the following exported names are not in SUPPORTED_COMMANDS.md: $($unexpected -join ', ')"
    }
}
