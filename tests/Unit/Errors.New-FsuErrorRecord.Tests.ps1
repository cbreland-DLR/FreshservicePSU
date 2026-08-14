<#
.SYNOPSIS
    Unit tests for New-FsuErrorRecord and New-FsuResponse (ARCHITECTURE.md
    §11, §13).
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Errors/New-FsuResponse.ps1')
}

Describe 'New-FsuErrorRecord' {

    It 'builds an ErrorRecord with the supplied FullyQualifiedErrorId and category' {
        $record = New-FsuErrorRecord -ErrorId 'FreshservicePSU.Test.Sample' -Message 'sample message' -Category InvalidData
        $record.FullyQualifiedErrorId | Should -Be 'FreshservicePSU.Test.Sample'
        $record.CategoryInfo.Category | Should -Be 'InvalidData'
        $record.Exception.Message | Should -Be 'sample message'
    }

    It 'carries CorrelationId and Field on the exception Data collection, not on the message' {
        $record = New-FsuErrorRecord -ErrorId 'FreshservicePSU.Test.Sample' -Message 'sample message' -Category InvalidData -CorrelationId 'corr-123' -Field 'subject'
        $record.Exception.Data['CorrelationId'] | Should -Be 'corr-123'
        $record.Exception.Data['Field'] | Should -Be 'subject'
    }

    It 'never includes a secret value supplied as an unrelated string in its formatted output' {
        $secretValue = 'sk_live_super_secret_value_12345'
        $record = New-FsuErrorRecord -ErrorId 'FreshservicePSU.Test.Sample' -Message 'a benign message' -Category InvalidData
        ($record | Out-String) | Should -Not -Match ([regex]::Escape($secretValue))
    }
}

Describe 'New-FsuResponse' {

    It 'builds a Freshservice.Response object with the given status and correlation id' {
        $response = New-FsuResponse -StatusCode 200 -CorrelationId 'corr-abc' -Body @{ id = 1 } -RateLimitTotal 500 -RateLimitRemaining 450 -RateLimitUsedCurrentRequest 1
        $response.PSObject.TypeNames | Should -Contain 'Freshservice.Response'
        $response.StatusCode | Should -Be 200
        $response.CorrelationId | Should -Be 'corr-abc'
        $response.RateLimit.Total | Should -Be 500
        $response.RateLimit.Remaining | Should -Be 450
        $response.RateLimit.UsedCurrentRequest | Should -Be 1
        $response.Body.id | Should -Be 1
    }

    # Phase 4's pager reads this off the envelope rather than raw headers.
    It 'carries the pagination link header on the envelope' {
        $link = '<https://acme.freshservice.com/api/v2/tickets?page=2>; rel="next"'
        $response = New-FsuResponse -StatusCode 200 -CorrelationId 'corr-abc' -Body @{} -Link $link
        $response.Link | Should -Be $link
    }

    It 'leaves Link empty for a non-paged response' {
        $response = New-FsuResponse -StatusCode 200 -CorrelationId 'corr-abc' -Body @{}
        $response.Link | Should -BeNullOrEmpty
    }

    It 'accepts a null Body without throwing' {
        { New-FsuResponse -StatusCode 204 -CorrelationId 'corr-xyz' -Body $null } | Should -Not -Throw
    }

    It 'never carries an authorization value in its formatted output' {
        $response = New-FsuResponse -StatusCode 200 -CorrelationId 'corr-abc' -Body @{ id = 1 }
        ($response | Out-String) | Should -Not -Match 'Authorization|Bearer '
    }
}
