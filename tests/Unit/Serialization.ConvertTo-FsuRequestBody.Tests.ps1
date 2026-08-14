<#
.SYNOPSIS
    Unit tests for ConvertTo-FsuRequestBody (ARCHITECTURE.md §11
    "Serialization conventions").
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Serialization/ConvertTo-FsuRequestBody.ps1')

    function ConvertFrom-FsuBody {
        param([byte[]]$Bytes)
        [System.Text.Encoding]::UTF8.GetString($Bytes) | ConvertFrom-Json
    }

    function Get-FsuBodyJsonText {
        param([byte[]]$Bytes)
        [System.Text.Encoding]::UTF8.GetString($Bytes)
    }

    function New-FsuTestSecureString {
        [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test fixture only; a SecureString built from a literal is required to exercise the refusal path.')]
        [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
        param([Parameter(Mandatory)][string]$PlainText)
        ConvertTo-SecureString $PlainText -AsPlainText -Force
    }
}

Describe 'ConvertTo-FsuRequestBody JSON basics' {

    It 'serializes with ConvertTo-Json -Depth 10 semantics (nested objects survive)' {
        $fields = @{ subject = 'a'; custom_fields = @{ nested = @{ deeper = @{ value = 1 } } } }
        $bytes = ConvertTo-FsuRequestBody -Fields $fields -BoundParameterNames @('subject', 'custom_fields')
        $obj = ConvertFrom-FsuBody -Bytes $bytes
        $obj.custom_fields.nested.deeper.value | Should -Be 1
    }

    It 'encodes UTF-8 without a byte-order mark' {
        $bytes = ConvertTo-FsuRequestBody -Fields @{ subject = 'café' } -BoundParameterNames @('subject')
        # UTF-8 BOM is EF BB BF; the first three bytes must not match it.
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $hasBom | Should -Be $false
    }
}

Describe 'ConvertTo-FsuRequestBody date conversion' {

    It 'converts a Local DateTime to UTC ISO 8601, not merely relabeling it' {
        $local = [datetime]::SpecifyKind((Get-Date '2026-01-01T12:00:00'), [System.DateTimeKind]::Local)
        $expectedUtc = $local.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $bytes = ConvertTo-FsuRequestBody -Fields @{ due_by = $local } -BoundParameterNames @('due_by')
        # Compare against the raw JSON text: ConvertFrom-Json auto-parses
        # ISO 8601 strings back into [datetime], which would re-introduce
        # the exact Local/Utc ambiguity this test is checking for.
        (Get-FsuBodyJsonText -Bytes $bytes) | Should -Match ([regex]::Escape($expectedUtc))
    }

    It 'passes a Utc DateTime through as ISO 8601 UTC unchanged' {
        $utc = [datetime]::SpecifyKind((Get-Date '2026-01-01T12:00:00'), [System.DateTimeKind]::Utc)
        $bytes = ConvertTo-FsuRequestBody -Fields @{ due_by = $utc } -BoundParameterNames @('due_by')
        (Get-FsuBodyJsonText -Bytes $bytes) | Should -Match ([regex]::Escape('2026-01-01T12:00:00Z'))
    }

    It 'treats an Unspecified DateTime as already UTC (assumed, not converted)' {
        $unspecified = [datetime]::SpecifyKind((Get-Date '2026-01-01T12:00:00'), [System.DateTimeKind]::Unspecified)
        $bytes = ConvertTo-FsuRequestBody -Fields @{ due_by = $unspecified } -BoundParameterNames @('due_by')
        (Get-FsuBodyJsonText -Bytes $bytes) | Should -Match ([regex]::Escape('2026-01-01T12:00:00Z'))
    }

}

Describe 'ConvertTo-FsuRequestBody null handling' {

    It 'omits an unbound parameter entirely from the body' {
        $bytes = ConvertTo-FsuRequestBody -Fields @{ subject = 'a'; description = 'b' } -BoundParameterNames @('subject')
        $obj = ConvertFrom-FsuBody -Bytes $bytes
        $obj.PSObject.Properties.Name | Should -Not -Contain 'description'
    }

    It 'sends an explicitly-bound $null parameter as JSON null' {
        $bytes = ConvertTo-FsuRequestBody -Fields @{ subject = 'a'; description = $null } -BoundParameterNames @('subject', 'description')
        $json = [System.Text.Encoding]::UTF8.GetString($bytes)
        $json | Should -Match '"description":\s*null'
    }
}

Describe 'ConvertTo-FsuRequestBody enum handling' {
    It 'sends the validated enum string verbatim, never remapped' {
        $bytes = ConvertTo-FsuRequestBody -Fields @{ status = 'Open' } -BoundParameterNames @('status')
        $obj = ConvertFrom-FsuBody -Bytes $bytes
        $obj.status | Should -Be 'Open'
    }
}

Describe 'ConvertTo-FsuRequestBody SecureString refusal' {
    It 'throws when a top-level field is a SecureString' {
        $secure = New-FsuTestSecureString -PlainText 'hunter2'
        { ConvertTo-FsuRequestBody -Fields @{ api_key = $secure } -BoundParameterNames @('api_key') } | Should -Throw
    }

    It 'throws when a SecureString is nested inside a hashtable field' {
        $secure = New-FsuTestSecureString -PlainText 'hunter2'
        { ConvertTo-FsuRequestBody -Fields @{ auth = @{ key = $secure } } -BoundParameterNames @('auth') } | Should -Throw
    }

    It 'never leaks the SecureString plaintext into the thrown error message' {
        $secure = New-FsuTestSecureString -PlainText 'hunter2-marker'
        $message = $null
        try {
            ConvertTo-FsuRequestBody -Fields @{ api_key = $secure } -BoundParameterNames @('api_key') | Out-Null
        } catch {
            $message = $_.Exception.Message
        }
        $message | Should -Not -BeNullOrEmpty
        $message | Should -Not -Match 'hunter2-marker'
    }
}
